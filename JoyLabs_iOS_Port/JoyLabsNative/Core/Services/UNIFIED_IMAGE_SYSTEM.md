# Unified Image System Documentation

## Overview

The Unified Image System provides a single, consistent code path for all image operations in the JoyLabs iOS app. It replaces the previous fractured system with a streamlined architecture that handles upload, caching, database mapping, and real-time UI refresh.

## Architecture

### Core Components

1. **UnifiedImageService** - Single source of truth for all image operations
2. **UnifiedImageView** - Single UI component for displaying images
3. **UnifiedImagePickerModal** - Single modal for image upload with TOCropViewController integration

### Key Features

- ✅ **Single Code Path**: All image operations flow through UnifiedImageService
- ✅ **Real-time Refresh**: Images update instantly across all views when uploaded
- ✅ **Automatic Cleanup**: Old cached images are automatically removed
- ✅ **Consistent UI**: All components use the same image loading logic
- ✅ **Context-Aware**: Different upload scenarios handled seamlessly
- ✅ **TOCropViewController**: Instagram-style 1:1 cropping integrated
- ✅ **Performance**: Optimized caching and loading strategies

## Usage

### Displaying Images

Replace all instances of `CachedImageView.catalogItem` with `UnifiedImageView`:

```swift
// OLD (DEPRECATED)
CachedImageView.catalogItem(
    imageURL: imageURL,
    imageId: imageId,
    size: 50
)

// NEW (UNIFIED)
UnifiedImageView.thumbnail(
    imageURL: imageURL,
    imageId: imageId,
    itemId: itemId,  // Required for proper refresh
    size: 50
)
```

### Convenience Methods

```swift
// For thumbnails (50px default)
UnifiedImageView.thumbnail(
    imageURL: imageURL,
    imageId: imageId,
    itemId: itemId
)

// For catalog items (100px)
UnifiedImageView.catalogItem(
    imageURL: imageURL,
    imageId: imageId,
    itemId: itemId,
    size: 100
)

// For large displays (200px)
UnifiedImageView.large(
    imageURL: imageURL,
    imageId: imageId,
    itemId: itemId,
    size: 200
)
```

### Image Upload

Replace all instances of `ImagePickerModal` with `UnifiedImagePickerModal`:

```swift
// OLD (DEPRECATED)
ImagePickerModal(
    context: .itemDetails(itemId: itemId),
    onDismiss: { /* ... */ },
    onImageUploaded: { result in
        // Manual refresh logic
    }
)

// NEW (UNIFIED)
UnifiedImagePickerModal(
    context: .itemDetails(itemId: itemId),
    onDismiss: { /* ... */ },
    onImageUploaded: { result in
        // UnifiedImageService handles all refresh automatically
    }
)
```

## Upload Contexts

The system supports different upload contexts:

```swift
enum ImageUploadContext {
    case itemDetails(itemId: String?)
    case scanViewLongPress(itemId: String, imageId: String?)
    case reordersViewLongPress(itemId: String, imageId: String?)
}
```

## Notification System

The unified system uses two notification types for real-time updates:

### .forceImageRefresh
Posted when images need immediate refresh across all views:
```swift
NotificationCenter.default.post(name: .forceImageRefresh, object: nil, userInfo: [
    "itemId": itemId,
    "oldImageId": oldImageId,
    "newImageId": newImageId
])
```

### .imageUpdated
Posted when specific item images are updated:
```swift
NotificationCenter.default.post(name: .imageUpdated, object: nil, userInfo: [
    "itemId": itemId,
    "imageId": newImageId,
    "imageURL": cacheURL,
    "action": "uploaded"
])
```

## Cache Management

### Automatic Cleanup
- Old cached images are automatically marked as stale when new ones are uploaded
- Memory cache is cleared for replaced images
- Physical cache files are cleaned up during regular maintenance

### Cache URL Format
- Internal cache URLs use format: `cache://[cacheKey]`
- AWS URLs are automatically converted to cache URLs
- Cache keys are mapped to Square image IDs in the database

## Error Handling

The system includes comprehensive error handling:

```swift
enum UnifiedImageError: LocalizedError {
    case databaseNotConnected
    case invalidImageData(String)
    case uploadFailed(String)
    case cacheOperationFailed(String)
}
```

## Migration Guide

### Step 1: Replace Image Views
Find and replace all instances of:
- `CachedImageView.catalogItem` → `UnifiedImageView.catalogItem`
- Add required `itemId` parameter

### Step 2: Replace Image Pickers
Find and replace all instances of:
- `ImagePickerModal` → `UnifiedImagePickerModal`
- Remove manual refresh logic from `onImageUploaded`

### Step 3: Remove Deprecated Code
- Remove custom refresh triggers (`@State private var refreshTrigger`)
- Remove manual notification handling for image updates
- Remove `.id(refreshTrigger)` modifiers

## Troubleshooting

### Images Not Refreshing
1. Ensure `itemId` is provided to `UnifiedImageView`
2. Check that notifications are being posted by `UnifiedImageService`
3. Verify the item ID matches between upload and display

### Upload Failures
1. Check network connectivity
2. Verify Square API credentials
3. Ensure image data is valid (< 15MB, > 1KB)
4. Check database connection

### Cache Issues
1. Clear app data to reset cache
2. Check disk space availability
3. Verify cache directory permissions

## Performance Considerations

- Images are cached in memory and on disk
- Cache keys are mapped to Square image IDs for consistency
- Old images are automatically cleaned up to prevent storage bloat
- Network requests are optimized with proper timeout values

## Future Enhancements

The unified system is designed to be easily extensible:
- Additional upload contexts can be added to `ImageUploadContext`
- New convenience methods can be added to `UnifiedImageView`
- Cache strategies can be enhanced in `UnifiedImageService`
- Additional notification types can be added for specific use cases
