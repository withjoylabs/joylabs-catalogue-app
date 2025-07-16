# JoyLabs Native iOS - Image Architecture Documentation

## 🎯 **Overview**

This document explains how our Swift native iOS app handles images from Square's catalog API, including the complete data flow, caching strategy, and common pitfalls to avoid.

## 🏗️ **Architecture Components**

### 1. **Image Data Flow Pipeline**
```
Square API → Sync Service → Database Storage → Search Results → UI Display
     ↓              ↓              ↓              ↓              ↓
AWS URLs    Image Mappings   SQLite Cache   CatalogImage   CachedImageView
```

### 2. **Core Components**

#### **SQLiteSwiftCatalogSyncService**
- Processes IMAGE objects from Square's ListCatalog API
- Creates item-to-image mappings during sync
- Handles orphaned image detection and cleanup

#### **ImageURLManager** 
- Manages image URL mappings in SQLite database
- Maps Square image IDs to AWS URLs and local cache keys
- Provides on-demand image loading capabilities

#### **ImageCacheService**
- Downloads images from AWS URLs on-demand
- Stores images locally with cache:// URLs
- Implements rate limiting to prevent AWS throttling

#### **CachedImageView (SwiftUI)**
- Displays images in search results and UI
- Handles loading states and fallbacks
- Supports both cached and AWS URLs

## 🔄 **Complete Data Flow**

### **Phase 1: Catalog Sync**
1. **Square API Response**: Returns ITEM and IMAGE objects
2. **Image Processing**: 
   - Store IMAGE objects with AWS URLs
   - Create image URL mappings (Square ID → AWS URL → Cache Key)
3. **Item-to-Image Mapping**:
   - Search for items that reference each image ID
   - Create mappings between items and their images
   - Mark orphaned images for cleanup

### **Phase 2: Search & Display**
1. **Search Query**: User searches for items
2. **Database Lookup**: Find matching items with image mappings
3. **Image Loading**: 
   - Check local cache first (cache:// URLs)
   - Download from AWS if cache miss
   - Store in local cache for future use
4. **UI Display**: Show thumbnails in search results

## 🚨 **Critical Pitfalls & Solutions**

### **1. Snake_case vs camelCase Field Names**
**❌ PITFALL**: Square API uses `image_ids` but Swift expects `imageIds`
```swift
// WRONG - Will fail silently
let imageIds = itemData["imageIds"] as? [String] ?? []

// CORRECT - Use snake_case for Square API
let imageIds = itemData["image_ids"] as? [String] ?? []
```

### **2. Orphaned Images from Deleted Items**
**❌ PITFALL**: Square's ListCatalog excludes deleted items but includes their orphaned images
- **Problem**: Wastes storage/bandwidth downloading images for non-existent items
- **Solution**: Detect orphaned images during sync and mark as deleted
```swift
// Check if image has corresponding items
if debugCount == 0 {
    logger.warning("🚨 ORPHANED IMAGE DETECTED: \(imageId)")
    try imageURLManager.markImageAsDeleted(squareImageId: imageId)
}
```

### **3. Database Initialization Timing**
**❌ PITFALL**: Database not initialized until user visits profile page
- **Problem**: Search fails with `databaseNotConnected` errors
- **Solution**: Initialize database on app launch, not on profile visit

### **4. Processing Order Dependencies**
**❌ PITFALL**: Creating item-to-image mappings during ITEM processing
- **Problem**: Image URLs don't exist in database yet when items are processed
- **Solution**: Create mappings during IMAGE processing phase after URLs are stored

### **5. AWS Rate Limiting**
**❌ PITFALL**: Downloading all images during sync
- **Problem**: AWS throttles requests, causing failures
- **Solution**: On-demand downloading during search with rate limiting

## 🛠️ **Implementation Best Practices**

### **Database Schema**
```sql
-- Image URL mappings table
CREATE TABLE image_url_mappings (
    square_image_id TEXT PRIMARY KEY,
    original_aws_url TEXT NOT NULL,
    local_cache_key TEXT NOT NULL,
    object_type TEXT NOT NULL,
    object_id TEXT NOT NULL,
    image_type TEXT NOT NULL,
    is_deleted INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_accessed_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### **Error Handling**
- Always check database connection before image operations
- Gracefully handle AWS download failures
- Provide fallback UI for missing images

### **Performance Optimization**
- Use database indexes on frequently queried fields
- Implement lazy loading for search results
- Cache images locally to reduce AWS requests
- Clean up orphaned images to save storage

## 🔧 **Debugging Tips**

### **Common Error Messages**
- `databaseNotConnected`: Database not initialized properly
- `Cache miss for image`: Normal - downloading from AWS
- `ORPHANED IMAGE DETECTED`: Expected - cleaning up deleted item images

### **Logging Strategy**
- Minimal logging during normal operation
- Detailed logging only for errors and warnings
- Use structured logging with clear prefixes (📷, 🔍, ✅, ❌)

## 📊 **Monitoring & Metrics**

### **Key Metrics to Track**
- Image cache hit/miss ratio
- AWS download success rate
- Orphaned image cleanup count
- Database query performance

### **Health Checks**
- Verify database connection on app launch
- Test image loading pipeline end-to-end
- Monitor AWS rate limiting responses

## 🚀 **Future Enhancements**

1. **Webhook Integration**: Real-time updates from Square
2. **Image Compression**: Optimize storage and bandwidth
3. **Prefetching**: Download popular images proactively
4. **CDN Integration**: Reduce AWS dependency

---

**Last Updated**: July 2025  
**Version**: 1.0  
**Maintainer**: JoyLabs Development Team
