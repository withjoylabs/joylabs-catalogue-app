import React, { useState, useEffect, useCallback } from 'react';
import { View, Text, TextInput, Switch, StyleSheet } from 'react-native';
import { generateClient, type GraphQLResult } from 'aws-amplify/api';
import { useAuthenticator } from '@aws-amplify/ui-react-native';
import * as queries from '../../src/graphql/queries';
import * as mutations from '../../src/graphql/mutations';
import type { ItemData, ItemChangeLog, Note } from '../../src/models';
import { lightTheme } from '../../src/themes';
import logger from '../../src/utils/logger';
import { itemHistoryService } from '../../src/services/itemHistoryService';

const client = generateClient();

interface TeamDataSectionProps {
  itemId: string;
  onSaveRef: React.MutableRefObject<(() => Promise<void>) | null>;
  onDataChange?: (hasChanges: boolean) => void;
}

export default function TeamDataSection({ itemId, onSaveRef, onDataChange }: TeamDataSectionProps) {
  const [itemData, setItemData] = useState<Partial<ItemData> | null>(null);
  const [originalItemData, setOriginalItemData] = useState<Partial<ItemData> | null>(null);
  const [changeLogs, setChangeLogs] = useState<(ItemChangeLog | null)[]>([]);
  const { user } = useAuthenticator((context) => [context.user]);

  const hasTeamDataChanges = useCallback((current: Partial<ItemData> | null, original: Partial<ItemData> | null): boolean => {
    if (!current && !original) return false;
    if (!current || !original) {
      const dataToCheck = current || original;
      return !!(
        dataToCheck?.caseUpc?.trim() ||
        dataToCheck?.caseCost ||
        dataToCheck?.caseQuantity ||
        dataToCheck?.vendor?.trim() ||
        dataToCheck?.discontinued ||
        dataToCheck?.notes?.[0]?.content?.trim()
      );
    }

    return (
      current.caseUpc !== original.caseUpc ||
      current.caseCost !== original.caseCost ||
      current.caseQuantity !== original.caseQuantity ||
      current.vendor !== original.vendor ||
      current.discontinued !== original.discontinued ||
      current.notes?.[0]?.content !== original.notes?.[0]?.content
    );
  }, []);

  useEffect(() => {
    if (onDataChange) {
      const hasChanges = hasTeamDataChanges(itemData, originalItemData);
      onDataChange(hasChanges);
    }
  }, [itemData, originalItemData, hasTeamDataChanges, onDataChange]);

  useEffect(() => {
    const fetchCustomItemData = async () => {
      if (!itemId) return;
      
      // Skip data fetching if user is not authenticated
      if (!user?.signInDetails?.loginId) {
        logger.info('TeamDataSection:fetchCustomItemData', 'Skipping data fetch - user not authenticated', { itemId });
        return;
      }
      
      try {
        const response = await client.graphql({ 
          query: queries.getItemData, 
          variables: { id: itemId }
        }) as GraphQLResult<{ getItemData: ItemData }>;
        
        if (response.data?.getItemData) {
          setItemData(response.data.getItemData);
          setOriginalItemData(response.data.getItemData);
        } else {
          setItemData(null);
          setOriginalItemData(null);
        }

        const logResponse = await client.graphql({
          query: queries.listChangesForItem,
          variables: { itemID: itemId, sortDirection: 'DESC' }
        }) as GraphQLResult<{ listChangesForItem: { items: (ItemChangeLog | null)[] } }>;
        if (logResponse.data?.listChangesForItem?.items) {
          setChangeLogs(logResponse.data.listChangesForItem.items);
        }
      } catch (e) {
        // Check if it's an authentication error
        const errorMessage = (e as any)?.message || String(e);
        if (errorMessage.includes('not authorized') || errorMessage.includes('Unauthenticated') || errorMessage.includes('UNAUTHENTICATED')) {
          logger.info('TeamDataSection:fetchCustomItemData', 'Skipping data fetch - authentication required', { itemId });
          return;
        }
        
        logger.error('TeamDataSection:fetchCustomItemData', 'Error fetching custom data', e);
      }
    };
    fetchCustomItemData();
  }, [itemId, user]);

  const trackTeamDataChanges = useCallback(async (newData: Partial<ItemData>, originalData: Partial<ItemData> | null) => {
    // Gracefully handle unauthenticated users
    if (!user?.signInDetails?.loginId || !itemId) {
      logger.info('TeamDataSection:trackTeamDataChanges', 'Skipping team data change tracking - user not authenticated', {
        itemId,
        hasUser: !!user
      });
      return;
    }
    
    const userName = user.signInDetails.loginId.split('@')[0] || 'Unknown User';
    const itemName = 'Item'; // We don't have item name in this component, could be passed as prop if needed
    
    try {
      const changes: Promise<boolean>[] = [];
      
      // Track CRV changes (caseCost)
      if (originalData?.caseCost !== newData.caseCost) {
        changes.push(
          itemHistoryService.logCRVChange(
            itemId,
            itemName,
            originalData?.caseCost || undefined,
            newData.caseCost || undefined,
            userName
          )
        );
      }
      
      // Track discontinued status changes
      if (originalData?.discontinued !== newData.discontinued) {
        changes.push(
          itemHistoryService.logDiscontinuedChange(
            itemId,
            itemName,
            originalData?.discontinued || false,
            newData.discontinued || false,
            userName
          )
        );
      }
      
      // Track vendor changes
      if (originalData?.vendor !== newData.vendor) {
        changes.push(
          itemHistoryService.logVendorChange(
            itemId,
            itemName,
            originalData?.vendor || undefined,
            newData.vendor || undefined,
            userName
          )
        );
      }
      
      // Track notes changes
      const oldNotes = originalData?.notes?.[0]?.content;
      const newNotes = newData.notes?.[0]?.content;
      if (oldNotes !== newNotes) {
        changes.push(
          itemHistoryService.logNotesChange(
            itemId,
            itemName,
            oldNotes,
            newNotes,
            userName
          )
        );
      }
      
      // Execute all change logging in parallel
      if (changes.length > 0) {
        await Promise.allSettled(changes);
        logger.info('TeamDataSection:trackTeamDataChanges', 'Successfully logged team data changes', {
          itemId,
          changeCount: changes.length
        });
      }
      
    } catch (error) {
      logger.error('TeamDataSection:trackTeamDataChanges', 'Error tracking team data changes', { error, itemId });
      // Don't fail the save operation if history tracking fails
    }
  }, [user, itemId]);

  const saveItemData = useCallback(async () => {
    if (!itemData || !itemId) return;
    try {
      const { __typename, id, createdAt, updatedAt, owner, ...inputData } = itemData as any;
      
      const existingRecord = await client.graphql({
        query: queries.getItemData,
        variables: { id: itemId }
      }) as GraphQLResult<{ getItemData: ItemData }>;

      // Track changes before saving
      await trackTeamDataChanges(itemData, originalItemData);

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

      setOriginalItemData({ ...itemData });
      logger.info('TeamDataSection:saveItemData', 'Team data saved successfully', { itemId });
    } catch (e) {
      logger.error('TeamDataSection:saveItemData', 'Error saving custom item data', e);
    }
  }, [itemId, itemData, trackTeamDataChanges, originalItemData]);
  
  useEffect(() => {
    if (onSaveRef) {
      onSaveRef.current = saveItemData;
    }
  }, [onSaveRef, saveItemData]);

  // Authentication guard - show sign-in prompt if user is not authenticated
  if (!user?.signInDetails?.loginId) {
    return (
      <View style={styles.teamDataSection}>
        <Text style={styles.teamDataTitle}>Team Data (Not Synced with Square)</Text>
        <View style={styles.authPromptContainer}>
          <Text style={styles.authPromptTitle}>Sign In Required</Text>
          <Text style={styles.authPromptText}>
            You must be signed in to view and edit team-specific data such as case information, vendor details, and internal notes.
          </Text>
          <Text style={styles.authPromptSubtext}>
            Please sign in to access this section.
          </Text>
        </View>
      </View>
    );
  }

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
    authPromptContainer: { 
        backgroundColor: '#f8f9fa', 
        borderRadius: 8, 
        padding: 20, 
        marginVertical: 16, 
        borderWidth: 1, 
        borderColor: '#dee2e6',
        alignItems: 'center'
    },
    authPromptTitle: { 
        fontSize: 18, 
        fontWeight: '600', 
        color: '#495057', 
        marginBottom: 8,
        textAlign: 'center'
    },
    authPromptText: { 
        fontSize: 16, 
        color: '#6c757d', 
        textAlign: 'center', 
        lineHeight: 22,
        marginBottom: 8
    },
    authPromptSubtext: { 
        fontSize: 14, 
        color: '#868e96', 
        textAlign: 'center',
        fontStyle: 'italic'
    },
}); 