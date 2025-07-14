# Search Architecture Documentation

## Overview

This document describes the unified search architecture implemented in JoyLabsNative. The architecture was designed to eliminate multiple data retrieval pipelines and provide a single, maintainable source of truth for all search functionality.

## Architecture Principles

### 1. Single Source of Truth
- **One unified data retrieval function**: `getCompleteItemData()`
- **Consistent results**: All search types use the same data retrieval logic
- **Single maintenance point**: Changes only need to be made in one place

### 2. Schema-Aware Design
- **Database-aware queries**: Only queries columns that exist in the schema
- **Conditional data loading**: Team data is only queried when needed (case UPC searches)
- **Error-resistant**: Gracefully handles missing columns or tables

### 3. Tokenized Fuzzy Search
- **Multi-word support**: "excedr 2ct" finds items containing BOTH "excedr" AND "2ct"
- **AND logic**: All tokens must be present in the result
- **Case-insensitive**: Search is normalized to lowercase

## Search Flow

```
Search Term → Find Item IDs → getCompleteItemData() → Consistent Results
     ↓              ↓                    ↓                    ↓
   "exced"    [ID1, ID2, ID3]    [Complete Item Data]    [3 Results with Categories]
```

### Phase 1: Search Term Processing
1. **Input**: Raw search term (e.g., "excedr 2ct")
2. **Tokenization**: Split into individual tokens ["excedr", "2ct"]
3. **Normalization**: Convert to lowercase for case-insensitive matching

### Phase 2: Item ID Discovery
Each search type finds matching item IDs using optimized queries:

- **Name Search**: `items.name LIKE '%token1%' AND items.name LIKE '%token2%'`
- **SKU Search**: `variations.sku LIKE '%token1%' AND variations.sku LIKE '%token2%'`
- **UPC Search**: `variations.upc LIKE '%token1%' AND variations.upc LIKE '%token2%'`
- **Category Search**: `categories.name LIKE '%searchterm%'`
- **Case UPC Search**: `team_data.case_upc = 'exact_match'`

### Phase 3: Unified Data Retrieval
For each discovered item ID, `getCompleteItemData()` retrieves:

- **Basic item data**: ID, name, category ID, pre-stored category names
- **Variation data**: SKU, UPC, price (from first variation)
- **Team data**: Case UPC and cost (only when needed)

### Phase 4: Result Assembly
- **Deduplication**: Same item found by multiple search types is only included once
- **Consistent formatting**: All results use the same SearchResultItem structure
- **Category display**: All results show proper category information

## Database Schema Integration

### Core Tables
- **`catalog_items`**: Main item data with pre-stored category names
- **`item_variations`**: SKU, UPC, and pricing information
- **`team_data`**: Case UPC and cost data (optional)

### Key Optimizations
- **Pre-stored categories**: Category names are stored directly in items table for fast retrieval
- **Minimal JOINs**: Only joins necessary tables for each search type
- **Conditional queries**: Team data is only queried for case UPC searches

## Search Types Supported

### 1. Name Search
- **Query**: Tokenized LIKE patterns on item name
- **Use case**: "excedrin", "excedr 2ct"
- **Performance**: Direct index on item name

### 2. SKU Search
- **Query**: Tokenized LIKE patterns on variation SKU
- **Use case**: "EXCED", "ABC123"
- **Performance**: Index on variation SKU

### 3. UPC Search
- **Query**: Tokenized LIKE patterns on variation UPC
- **Use case**: "123456789", partial UPC searches
- **Performance**: Index on variation UPC

### 4. Category Search
- **Query**: LIKE pattern on category name
- **Use case**: "Health", "Medicine"
- **Performance**: Index on category name

### 5. Case UPC Search
- **Query**: Exact match on team data case UPC
- **Use case**: Wholesale/case-level product identification
- **Performance**: Index on case UPC

## Implementation Details

### Core Function: `getCompleteItemData()`

```swift
private func getCompleteItemData(
    itemId: String, 
    db: Connection, 
    matchType: String, 
    matchContext: String? = nil
) -> SearchResultItem?
```

**Parameters:**
- `itemId`: The unique item identifier
- `db`: Database connection
- `matchType`: Type of search that found this item ("name", "sku", "upc", "category", "case_upc")
- `matchContext`: The specific value that matched (item name, SKU value, etc.)

**Returns:** Complete SearchResultItem with all necessary data

### Search Result Structure

```swift
struct SearchResultItem {
    let id: String
    let name: String
    let sku: String?
    let price: Double?
    let barcode: String?
    let categoryId: String?
    let categoryName: String?
    let images: [String]?
    let matchType: String
    let matchContext: String?
    let isFromCaseUpc: Bool
    let caseUpcData: CaseUpcData?
    let hasTax: Bool
}
```

## Performance Characteristics

### Search Speed
- **Name/SKU/UPC searches**: ~10-50ms for typical queries
- **Category searches**: ~5-20ms (fewer results)
- **Case UPC searches**: ~1-5ms (exact match)

### Memory Usage
- **Minimal memory footprint**: Only loads necessary data
- **Efficient deduplication**: Uses Set-based deduplication
- **Lazy loading**: Results loaded on-demand with pagination

### Database Load
- **Optimized queries**: Minimal JOINs and targeted SELECT statements
- **Index utilization**: All search types use appropriate indexes
- **Connection reuse**: Single database connection per search operation

## Future Extensions

### Reorder Page Integration
This architecture is designed to be reused for the upcoming reorder page:

1. **Same search functionality**: Reorder page can use identical search methods
2. **Additional filters**: Easy to add date ranges, order history filters
3. **Performance**: Same optimized queries and caching

### Potential Enhancements
- **Full-text search**: Could integrate FTS for more advanced text matching
- **Search suggestions**: Could add autocomplete based on search history
- **Caching layer**: Could add Redis/memory cache for frequent searches
- **Analytics**: Could add search analytics and optimization

## Maintenance Guidelines

### Adding New Search Types
1. Create new search function following existing patterns
2. Ensure it returns item IDs only
3. Use `getCompleteItemData()` for result creation
4. Add to main search orchestration logic

### Modifying Data Retrieval
1. **Only modify `getCompleteItemData()`** - all search types will benefit
2. Ensure backward compatibility with existing SearchResultItem structure
3. Test all search types after changes

### Database Schema Changes
1. Update `getCompleteItemData()` to handle new columns
2. Ensure conditional querying for optional data
3. Update documentation with new schema requirements

## Testing Strategy

### Unit Tests
- Test each search type independently
- Test tokenization and normalization
- Test deduplication logic
- Test error handling

### Integration Tests
- Test complete search flow end-to-end
- Test with various database states
- Test performance with large datasets
- Test edge cases (empty results, special characters)

### Performance Tests
- Benchmark search speed with realistic data volumes
- Test memory usage under load
- Test concurrent search operations
