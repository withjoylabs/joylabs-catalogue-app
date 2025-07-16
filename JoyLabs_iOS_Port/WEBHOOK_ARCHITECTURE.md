# Webhook Integration Architecture for Image Cache Management

## Overview

This document outlines the architecture for integrating Square webhooks to maintain fresh image cache data in the JoyLabs iOS app. The webhook system ensures that local cached images stay synchronized with Square's catalog data without requiring full catalog re-syncs.

## Current Image Cache System

### Architecture Components

1. **ImageCacheService**: Handles image downloading, memory/disk caching, and retrieval
2. **ImageURLManager**: Manages mappings between Square image IDs and local cache keys
3. **Database Tables**:
   - `image_url_mappings`: Maps Square image IDs to local cache keys
   - `images`: Stores image metadata from Square catalog

### Cache URL Format
- **Internal URLs**: `cache://[cache_key]` for efficient local retrieval
- **AWS URLs**: Original Square-provided URLs for downloading
- **Cache Keys**: Generated from AWS URL + Square image ID for uniqueness

## Webhook Integration Strategy

### 1. Webhook Event Types to Handle

#### Catalog Object Events
- `catalog.version.updated`: When any catalog object changes
- `catalog.object.created`: New items/categories with images
- `catalog.object.updated`: Modified items/categories/images
- `catalog.object.deleted`: Removed items/categories/images

#### Image-Specific Events
- Focus on events affecting `ITEM`, `CATEGORY`, and `IMAGE` object types
- Track `image_ids` array changes in items and categories

### 2. Webhook Processing Pipeline

```
Square Webhook → Webhook Handler → Cache Invalidation → Background Refresh
```

#### Step 1: Webhook Reception
- Receive webhook payload with changed object information
- Validate webhook signature for security
- Parse object type and change details

#### Step 2: Cache Impact Analysis
- Determine which cached images are affected
- Check if object has image references (`image_ids` array)
- Identify stale cache entries

#### Step 3: Selective Cache Invalidation
- Mark affected image mappings as `is_deleted = true`
- Remove stale files from disk cache
- Clear memory cache entries
- Update `last_accessed_at` timestamps

#### Step 4: Background Refresh
- Queue background tasks to re-download updated images
- Update image mappings with new cache keys
- Maintain cache performance during updates

### 3. Implementation Components

#### WebhookHandler Service
```swift
class WebhookHandler {
    func processWebhook(_ payload: WebhookPayload) async
    func validateSignature(_ payload: Data, signature: String) -> Bool
    func extractAffectedImages(_ payload: WebhookPayload) -> [String]
}
```

#### CacheInvalidationService
```swift
class CacheInvalidationService {
    func invalidateImagesForObject(_ objectId: String, objectType: String) async
    func invalidateImageById(_ imageId: String) async
    func cleanupStaleCache() async
}
```

#### BackgroundRefreshService
```swift
class BackgroundRefreshService {
    func queueImageRefresh(_ imageIds: [String]) async
    func refreshImageInBackground(_ imageId: String) async
    func updateImageMapping(_ imageId: String, newUrl: String) async
}
```

## Cache Invalidation Strategies

### 1. Granular Invalidation
- **Item Updates**: Invalidate only images referenced by the specific item
- **Category Updates**: Invalidate category images and optionally item images in that category
- **Image Updates**: Invalidate the specific image across all references

### 2. Batch Processing
- Group multiple webhook events for efficient processing
- Debounce rapid successive updates to the same objects
- Process invalidations in background queues

### 3. Fallback Mechanisms
- If webhook processing fails, fall back to periodic sync checks
- Maintain cache expiration timestamps as backup
- Graceful degradation to AWS URLs if cache is unavailable

## Performance Considerations

### 1. Minimal UI Impact
- Process webhooks in background threads
- Update UI only when new images are ready
- Show cached images until replacements are available

### 2. Network Efficiency
- Download only changed images, not entire catalog
- Use HTTP caching headers when available
- Implement retry logic with exponential backoff

### 3. Storage Management
- Clean up orphaned cache files periodically
- Implement LRU eviction for disk cache
- Monitor cache size and performance metrics

## Security and Reliability

### 1. Webhook Security
- Validate Square webhook signatures
- Use HTTPS endpoints for webhook reception
- Implement rate limiting and abuse protection

### 2. Error Handling
- Retry failed webhook processing with backoff
- Log webhook processing errors for debugging
- Maintain system stability during webhook failures

### 3. Data Consistency
- Use database transactions for cache updates
- Implement atomic operations for cache invalidation
- Handle concurrent access to cache resources

## Implementation Phases

### Phase 1: Webhook Infrastructure
- Set up webhook endpoint and signature validation
- Implement basic webhook payload parsing
- Create database schema for webhook tracking

### Phase 2: Cache Invalidation
- Implement selective cache invalidation logic
- Add background refresh capabilities
- Test with Square sandbox webhooks

### Phase 3: Production Integration
- Deploy webhook endpoint to production
- Monitor webhook processing performance
- Implement comprehensive error handling

### Phase 4: Optimization
- Add batch processing and debouncing
- Implement advanced caching strategies
- Monitor and optimize performance metrics

## Monitoring and Metrics

### Key Metrics to Track
- Webhook processing latency
- Cache hit/miss ratios
- Image refresh success rates
- Storage usage and cleanup efficiency

### Alerting
- Failed webhook processing
- High cache miss rates
- Storage capacity issues
- Network connectivity problems

## Future Enhancements

### Advanced Features
- Predictive image pre-loading
- Image compression and optimization
- CDN integration for improved performance
- Real-time image updates in UI

### Integration Opportunities
- Sync with other Square data changes
- Cross-platform cache sharing
- Analytics on image usage patterns
- A/B testing for cache strategies

---

This architecture ensures that the JoyLabs app maintains fresh, performant image data while minimizing network usage and providing excellent user experience during catalog updates.
