import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, TextInput, Switch, StyleSheet } from 'react-native';
import { generateClient, type GraphQLResult } from 'aws-amplify/api';
import * as queries from '../../src/graphql/queries';
import * as mutations from '../../src/graphql/mutations';
import type { ItemData, ItemChangeLog, Note } from '../../src/models';
import { lightTheme } from '../../src/themes';
import logger from '../../src/utils/logger';

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
        const response = await client.graphql({ 
          query: queries.getItemData, 
          variables: { id: itemId }
        }) as GraphQLResult<{ getItemData: ItemData }>;
        if (response.data?.getItemData) {
          setItemData(response.data.getItemData);
        }

        const logResponse = await client.graphql({
          query: queries.listChangesForItem,
          variables: { itemID: itemId, sortDirection: 'DESC' }
        }) as GraphQLResult<{ listChangesForItem: { items: (ItemChangeLog | null)[] } }>;
        if (logResponse.data?.listChangesForItem?.items) {
          setChangeLogs(logResponse.data.listChangesForItem.items);
        }
      } catch (e) {
        logger.error('TeamDataSection:fetchCustomItemData', 'Error fetching custom data', e);
      }
    };
    fetchCustomItemData();
  }, [itemId]);

  const saveItemData = useCallback(async () => {
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
  }, [itemId, itemData]);
  
  useEffect(() => {
    if (onSaveRef) {
      onSaveRef.current = saveItemData;
    }
  }, [onSaveRef, saveItemData]);

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