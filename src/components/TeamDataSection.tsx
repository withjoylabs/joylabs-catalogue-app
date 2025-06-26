import React, { useState, useEffect } from 'react';
import { View, Text, TextInput, Switch, StyleSheet } from 'react-native';
import { generateClient, type GraphQLResult } from 'aws-amplify/api';
import * as queries from '../graphql/queries';
import * as mutations from '../graphql/mutations';
import { ItemData, ItemChangeLog, Note } from '../models';
import { lightTheme } from '../themes';
import logger from '../utils/logger';
import * as modernDb from '../database/modernDb';
import appSyncMonitor from '../services/appSyncMonitor';

const client = generateClient();

interface TeamDataSectionProps {
  itemId: string;
  onSaveRef: React.MutableRefObject<(() => Promise<void>) | null>;
}

export default function TeamDataSection({ itemId, onSaveRef }: TeamDataSectionProps) {
  const [itemData, setItemData] = useState<Partial<ItemData> | null>(null);
  const [changeLogs, setChangeLogs] = useState<(ItemChangeLog | null)[]>([]);

  useEffect(() => {
    const fetchCustomItemData = async () => {
      if (!itemId) return;
      try {
        logger.info('TeamDataSection:fetchCustomItemData', '🔍 Loading team data locally (LOCAL-FIRST)', { itemId });

        // ✅ CRITICAL FIX: Get from local SQLite first (LOCAL-FIRST ARCHITECTURE)
        const localTeamData = await modernDb.getTeamData(itemId);

        if (localTeamData) {
          setItemData({
            id: localTeamData.itemId,
            caseUpc: localTeamData.caseUpc,
            caseCost: localTeamData.caseCost,
            caseQuantity: localTeamData.caseQuantity,
            vendor: localTeamData.vendor,
            discontinued: localTeamData.discontinued,
            notes: localTeamData.notes ? [{
              id: 'local-note',
              content: localTeamData.notes,
              isComplete: false,
              authorId: 'local',
              authorName: 'local',
              createdAt: localTeamData.createdAt || new Date().toISOString(),
              updatedAt: localTeamData.updatedAt || new Date().toISOString()
            }] : []
          });
          logger.info('TeamDataSection:fetchCustomItemData', '✅ Team data loaded from local database');

          // ✅ NO TIME-BASED POLLING: Data syncs only via webhooks/AppSync or CRUD operations
        } else {
          logger.info('TeamDataSection:fetchCustomItemData', '📭 No local team data found - attempting recovery from DynamoDB');
          // ✅ INITIAL RECOVERY: When local data is missing, try to recover from DynamoDB once
          await recoverTeamDataFromDynamoDB(itemId);
        }

        // Always try to load change logs locally first (TODO: implement local change log storage)
        // For now, still use AppSync for change logs but this should be moved to local storage too
        const logResponse = await client.graphql({
          query: queries.listChangesForItem,
          variables: { itemID: itemId, sortDirection: 'DESC' }
        }) as GraphQLResult<{ listChangesForItem: { items: (ItemChangeLog | null)[] } }>;
        if (logResponse.data?.listChangesForItem?.items) {
          setChangeLogs(logResponse.data.listChangesForItem.items);
        }
      } catch (e) {
        logger.error('TeamDataSection:fetchCustomItemData', '❌ Error fetching team data', e);
      }
    };

    // ✅ INITIAL RECOVERY: Recover team data from DynamoDB when local data is missing
    const recoverTeamDataFromDynamoDB = async (itemId: string) => {
      try {
        logger.info('TeamDataSection:recoverTeamDataFromDynamoDB', '🔄 Recovering team data from DynamoDB (initial recovery)', { itemId });

        // Monitor AppSync request
        await appSyncMonitor.beforeRequest('getItemData', 'TeamDataSection:initialRecovery', { id: itemId });

        const response = await client.graphql({
          query: queries.getItemData,
          variables: { id: itemId }
        }) as GraphQLResult<{ getItemData: ItemData }>;

        if (response.data?.getItemData) {
          const data = response.data.getItemData;
          const teamData: modernDb.TeamData = {
            itemId: data.id,
            caseUpc: data.caseUpc || undefined,
            caseCost: data.caseCost || undefined,
            caseQuantity: data.caseQuantity || undefined,
            vendor: data.vendor || undefined,
            discontinued: data.discontinued || false,
            notes: data.notes?.[0]?.content || undefined,
            lastSyncAt: new Date().toISOString(),
            owner: data.owner || undefined
          };

          // Save to local database
          await modernDb.upsertTeamData(teamData);
          logger.info('TeamDataSection:recoverTeamDataFromDynamoDB', '✅ Team data recovered from DynamoDB and saved locally');

          // Update UI with recovered data
          setItemData({
            id: data.id,
            caseUpc: data.caseUpc,
            caseCost: data.caseCost,
            caseQuantity: data.caseQuantity,
            vendor: data.vendor,
            discontinued: data.discontinued,
            notes: data.notes ? [{
              id: 'recovered-note',
              content: data.notes[0]?.content || '',
              isComplete: false,
              authorId: 'recovered',
              authorName: 'recovered',
              createdAt: new Date().toISOString(),
              updatedAt: new Date().toISOString()
            }] : []
          });
        } else {
          logger.info('TeamDataSection:recoverTeamDataFromDynamoDB', '📭 No team data found in DynamoDB');
        }
      } catch (error) {
        logger.error('TeamDataSection:recoverTeamDataFromDynamoDB', '❌ Team data recovery from DynamoDB failed', { error, itemId });
      }
    };

    fetchCustomItemData();
  }, [itemId]);

  const saveItemData = async () => {
    if (!itemData || !itemId) return;
    try {
      const { __typename, id, createdAt, updatedAt, owner, ...inputData } = itemData as any;
      
      const existingRecord = await client.graphql({
        query: queries.getItemData,
        variables: { id: itemId }
      }) as GraphQLResult<{ getItemData: ItemData }>;

      if (existingRecord.data?.getItemData) {
        await client.graphql({
          query: mutations.updateItemData,
          variables: { input: { id: itemId, ...inputData } }
        });
      } else {
        await client.graphql({
          query: mutations.createItemData,
          variables: { input: { id: itemId, ...inputData } }
        });
      }
    } catch (e) {
      logger.error('TeamDataSection:saveItemData', 'Error saving custom item data', e);
    }
  };
  
  useEffect(() => {
    if (onSaveRef) {
      onSaveRef.current = saveItemData;
    }
  }, [itemData]);

  return (
    <View style={styles.teamDataSection}>
      <Text style={styles.teamDataTitle}>Team Data (Not Synced with Square)</Text>
      
      <View style={styles.fieldContainer}>
        <Text style={styles.label}>Case UPC</Text>
        <TextInput
          style={styles.input}
          value={itemData?.caseUpc || ''}
          onChangeText={(text) => setItemData((prev: any) => ({ ...prev, caseUpc: text }))}
          placeholder="Enter case UPC/barcode"
        />
      </View>
      <View style={styles.fieldContainer}>
        <Text style={styles.label}>Case Cost</Text>
        <TextInput
          style={styles.input}
          value={itemData?.caseCost?.toString() || ''}
          onChangeText={(text) => setItemData((prev: any) => ({ ...prev, caseCost: parseFloat(text) || undefined }))}
          placeholder="0.00"
          keyboardType="numeric"
        />
      </View>
      <View style={styles.fieldContainer}>
        <Text style={styles.label}>Case Quantity</Text>
        <TextInput
          style={styles.input}
          value={itemData?.caseQuantity?.toString() || ''}
          onChangeText={(text) => setItemData((prev: any) => ({ ...prev, caseQuantity: parseInt(text, 10) || undefined }))}
          placeholder="e.g., 12"
          keyboardType="numeric"
        />
      </View>
      <View style={styles.fieldContainer}>
        <Text style={styles.label}>Vendor</Text>
        <TextInput
          style={styles.input}
          value={itemData?.vendor || ''}
          onChangeText={(text) => setItemData((prev: any) => ({ ...prev, vendor: text }))}
          placeholder="Enter vendor name"
        />
      </View>
      <View style={styles.checkboxRow}>
        <Text style={styles.label}>Discontinued</Text>
        <Switch
          value={itemData?.discontinued || false}
          onValueChange={(value) => setItemData((prev: any) => ({ ...prev, discontinued: value }))}
        />
      </View>
      <View style={styles.fieldContainer}>
        <Text style={styles.label}>Additional Notes</Text>
        <TextInput
          style={[styles.input, styles.textArea]}
          value={itemData?.notes?.[0]?.content || ''}
          onChangeText={(text) => {
            const newNote: Note = { id: "local-note", content: text, isComplete: false, authorId: "local", authorName: "local", createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
            setItemData((prev: any) => ({ ...prev, notes: [newNote] }));
          }}
          placeholder="Internal notes about this item..."
          multiline
        />
      </View>

      <View style={styles.logContainer}>
        <Text style={styles.sectionHeaderText}>History</Text>
        {changeLogs.filter(log => log).map(log => (
          <View key={log!.id} style={styles.logItem}>
            <Text style={styles.logText}>{log!.changeDetails}</Text>
            <Text style={styles.logMeta}>
              {log!.authorName} - {new Date(log!.timestamp).toLocaleString()}
            </Text>
          </View>
        ))}
        {changeLogs.length === 0 && <Text>No history for this item.</Text>}
      </View>
    </View>
  );
}

// Re-defining styles locally for this component
const styles = StyleSheet.create({
    fieldContainer: { marginBottom: 20 },
    label: { fontSize: 16, fontWeight: '500', marginBottom: 8, color: '#333' },
    input: { borderWidth: 1, borderColor: '#ddd', borderRadius: 5, backgroundColor: 'white', padding: 12, fontSize: 16 },
    textArea: { height: 100, textAlignVertical: 'top' },
    teamDataSection: { marginTop: 24, paddingTop: 16, borderTopWidth: 1, borderTopColor: '#e0e0e0' },
    teamDataTitle: { fontSize: 20, fontWeight: 'bold', color: lightTheme.colors.primary, marginBottom: 16, textAlign: 'center' },
    checkboxRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 20, justifyContent: 'space-between' },
    logContainer: { marginTop: 16 },
    sectionHeaderText: { fontSize: 18, fontWeight: '600', marginBottom: 12, color: '#333' },
    logItem: { backgroundColor: '#f9f9f9', borderRadius: 5, padding: 10, marginBottom: 8, borderLeftWidth: 3, borderLeftColor: lightTheme.colors.primary },
    logText: { fontSize: 14, color: '#333' },
    logMeta: { fontSize: 12, color: '#777', marginTop: 4 },
}); 