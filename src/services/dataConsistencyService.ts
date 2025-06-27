import { getDatabase } from '../database/modernDb';
import { ReorderItem } from './reorderService';
import crossReferenceService from './crossReferenceService';
import logger from '../utils/logger';

/**
 * Data Consistency Service
 * 
 * Checks for data consistency issues in the reorder system:
 * - Stale item data (items that no longer exist in Square catalog)
 * - Missing references (reorder items without corresponding catalog/team data)
 * - Sync conflicts (local vs server data mismatches)
 * - Orphaned data (team data without corresponding catalog items)
 */

export interface ConsistencyIssue {
  type: 'stale_item' | 'missing_catalog' | 'missing_team_data' | 'sync_conflict' | 'orphaned_data';
  severity: 'low' | 'medium' | 'high';
  itemId: string;
  description: string;
  details?: any;
}

export interface ConsistencyReport {
  totalIssues: number;
  issuesByType: Record<string, number>;
  issuesBySeverity: Record<string, number>;
  issues: ConsistencyIssue[];
  lastChecked: string;
}

class DataConsistencyService {
  private lastCheckTime: number = 0;
  private readonly CHECK_INTERVAL = 5 * 60 * 1000; // 5 minutes

  /**
   * Run comprehensive data consistency checks
   */
  async runConsistencyCheck(reorderItems: ReorderItem[]): Promise<ConsistencyReport> {
    const startTime = Date.now();
    logger.info('[DataConsistencyService]', 'Starting data consistency check...');

    const issues: ConsistencyIssue[] = [];

    try {
      // Check 1: Missing Square catalog data
      const catalogIssues = await this.checkMissingCatalogData(reorderItems);
      issues.push(...catalogIssues);

      // Check 2: Missing team data
      const teamDataIssues = await this.checkMissingTeamData(reorderItems);
      issues.push(...teamDataIssues);

      // Check 3: Stale references
      const staleIssues = await this.checkStaleReferences(reorderItems);
      issues.push(...staleIssues);

      // Check 4: Orphaned team data
      const orphanedIssues = await this.checkOrphanedTeamData();
      issues.push(...orphanedIssues);

      // Generate report
      const report = this.generateReport(issues);
      
      const duration = Date.now() - startTime;
      logger.info('[DataConsistencyService]', `Consistency check completed in ${duration}ms`, {
        totalIssues: report.totalIssues,
        issuesByType: report.issuesByType
      });

      this.lastCheckTime = Date.now();
      return report;

    } catch (error) {
      logger.error('[DataConsistencyService]', 'Error during consistency check', { error });
      return this.generateReport([]);
    }
  }

  /**
   * Check for reorder items with missing Square catalog data
   */
  private async checkMissingCatalogData(reorderItems: ReorderItem[]): Promise<ConsistencyIssue[]> {
    const issues: ConsistencyIssue[] = [];

    for (const item of reorderItems) {
      // Skip custom items
      if (item.itemId.startsWith('custom-')) continue;

      const squareItem = await crossReferenceService.getSquareItem(item.itemId);
      if (!squareItem) {
        issues.push({
          type: 'missing_catalog',
          severity: 'high',
          itemId: item.itemId,
          description: `Reorder item references non-existent Square catalog item`,
          details: { reorderItemId: item.id }
        });
      }
    }

    return issues;
  }

  /**
   * Check for reorder items with missing team data
   */
  private async checkMissingTeamData(reorderItems: ReorderItem[]): Promise<ConsistencyIssue[]> {
    const issues: ConsistencyIssue[] = [];

    for (const item of reorderItems) {
      // Skip custom items (they may not have team data)
      if (item.itemId.startsWith('custom-')) continue;

      const teamData = await crossReferenceService.getTeamData(item.itemId);
      if (!teamData) {
        issues.push({
          type: 'missing_team_data',
          severity: 'medium',
          itemId: item.itemId,
          description: `Reorder item has no team data (vendor, cost, etc.)`,
          details: { reorderItemId: item.id }
        });
      }
    }

    return issues;
  }

  /**
   * Check for stale references (items that exist in reorder but are deleted in catalog)
   */
  private async checkStaleReferences(reorderItems: ReorderItem[]): Promise<ConsistencyIssue[]> {
    const issues: ConsistencyIssue[] = [];

    try {
      const db = await getDatabase();
      
      for (const item of reorderItems) {
        // Skip custom items
        if (item.itemId.startsWith('custom-')) continue;

        // Check if item is marked as deleted in catalog
        const catalogItem = await db.getFirstAsync<any>(
          'SELECT is_deleted FROM catalog_items WHERE id = ?',
          item.itemId
        );

        if (catalogItem && catalogItem.is_deleted === 1) {
          issues.push({
            type: 'stale_item',
            severity: 'high',
            itemId: item.itemId,
            description: `Reorder item references deleted catalog item`,
            details: { reorderItemId: item.id }
          });
        }
      }
    } catch (error) {
      logger.error('[DataConsistencyService]', 'Error checking stale references', { error });
    }

    return issues;
  }

  /**
   * Check for orphaned team data (team data without corresponding catalog items)
   */
  private async checkOrphanedTeamData(): Promise<ConsistencyIssue[]> {
    const issues: ConsistencyIssue[] = [];

    try {
      const db = await getDatabase();
      
      // Find team data entries that don't have corresponding catalog items
      const orphanedData = await db.getAllAsync<any>(`
        SELECT td.item_id 
        FROM team_data td 
        LEFT JOIN catalog_items ci ON td.item_id = ci.id 
        WHERE ci.id IS NULL AND td.item_id NOT LIKE 'custom-%'
      `);

      for (const orphan of orphanedData) {
        issues.push({
          type: 'orphaned_data',
          severity: 'low',
          itemId: orphan.item_id,
          description: `Team data exists for non-existent catalog item`,
          details: {}
        });
      }
    } catch (error) {
      logger.error('[DataConsistencyService]', 'Error checking orphaned team data', { error });
    }

    return issues;
  }

  /**
   * Generate consistency report
   */
  private generateReport(issues: ConsistencyIssue[]): ConsistencyReport {
    const issuesByType: Record<string, number> = {};
    const issuesBySeverity: Record<string, number> = {};

    issues.forEach(issue => {
      issuesByType[issue.type] = (issuesByType[issue.type] || 0) + 1;
      issuesBySeverity[issue.severity] = (issuesBySeverity[issue.severity] || 0) + 1;
    });

    return {
      totalIssues: issues.length,
      issuesByType,
      issuesBySeverity,
      issues,
      lastChecked: new Date().toISOString()
    };
  }

  /**
   * Check if consistency check is needed (based on interval)
   */
  shouldRunCheck(): boolean {
    return Date.now() - this.lastCheckTime > this.CHECK_INTERVAL;
  }

  /**
   * Get human-readable description for issue type
   */
  getIssueTypeDescription(type: string): string {
    const descriptions = {
      'missing_catalog': 'Missing Square Catalog Data',
      'missing_team_data': 'Missing Team Data',
      'stale_item': 'Stale Item References',
      'sync_conflict': 'Sync Conflicts',
      'orphaned_data': 'Orphaned Team Data'
    };
    return descriptions[type] || type;
  }

  /**
   * Get color for issue severity
   */
  getSeverityColor(severity: string): string {
    const colors = {
      'low': '#FFA726',
      'medium': '#FF9500', 
      'high': '#FF3B30'
    };
    return colors[severity] || '#999';
  }
}

// Export singleton instance
export const dataConsistencyService = new DataConsistencyService();
export default dataConsistencyService;
