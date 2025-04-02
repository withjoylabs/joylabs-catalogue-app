# JoyLabs API Documentation

This document details the API endpoints used in the JoyLabs application, their request/response formats, and usage patterns.

## Base URL

All API endpoints use the following base URL:

```
https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production
```

## Authentication

All requests (except authentication endpoints) require authorization:

```
Authorization: Bearer {accessToken}
```

### Authentication Endpoints

#### Get Square Connect URL

```
GET /api/auth/connect/url
```

**Response:**
```json
{
  "url": "https://connect.squareup.com/oauth2/authorize?..."
}
```

#### Square Callback

```
GET /api/auth/square/callback
```

This endpoint is called by Square after user authorization. It exchanges the authorization code for tokens, then redirects back to the app using deep linking.

## Catalog Endpoints

### List Categories

```
GET /v2/catalog/list-categories
```

Retrieves all categories from the merchant's catalog.

**Response:**
```json
{
  "success": true,
  "objects": [
    {
      "id": "CATEGORY_ID",
      "type": "CATEGORY",
      "category_data": {
        "name": "Category Name"
      }
    }
  ],
  "count": 123,
  "cursor": "cursor_string"
}
```

### List Catalog Items

```
GET /v2/catalog/list?types=ITEM&limit=100
```

Retrieves catalog items with pagination support.

**Parameters:**
- `types`: Type of catalog objects to return (default: ITEM)
- `limit`: Maximum number of items to return (default: 20)
- `cursor`: Pagination cursor for subsequent requests

**Response:**
```json
{
  "success": true,
  "objects": [
    {
      "id": "ITEM_ID",
      "type": "ITEM",
      "item_data": {
        "name": "Item Name",
        "description": "Description",
        "variations": []
      }
    }
  ],
  "cursor": "cursor_string"
}
```

### Get Item Details

```
GET /v2/catalog/item/{itemId}
```

Retrieves detailed information about a specific catalog item.

**Response:**
```json
{
  "success": true,
  "object": {
    "id": "ITEM_ID",
    "type": "ITEM",
    "item_data": {
      "name": "Item Name",
      "description": "Description",
      "variations": []
    }
  }
}
```

### Search Catalog

```
POST /v2/catalog/search
```

Searches catalog objects with advanced filtering.

**Request Body:**
```json
{
  "object_types": ["ITEM"],
  "query": {
    "text_query": {
      "query": "search term"
    }
  },
  "limit": 100
}
```

**Response:**
```json
{
  "success": true,
  "objects": [],
  "cursor": "cursor_string"
}
```

## Webhooks

### Health Check

```
GET /api/webhooks/health
```

Checks API connectivity and health status.

**Response:**
```json
{
  "success": true,
  "timestamp": "2025-04-02T12:34:56Z"
}
```

## Error Responses

All endpoints return standardized error responses:

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable error message",
    "details": []
  }
}
```

## Implementation Notes

### API Client Usage

The frontend uses a centralized API client located in `src/api/index.ts`:

```typescript
// Example: Fetching categories
const categories = await api.catalog.getCategories();

// Example: Searching items
const searchResults = await api.catalog.searchItems({
  object_types: ["ITEM"],
  query: {
    text_query: {
      query: searchTerm
    }
  }
});
```

### Response Caching

The API client implements TTL-based caching:
- Categories: 5 minutes
- Catalog items: 2 minutes
- Search results: 2 minutes
- Health checks: Not cached

### Error Handling

Always check the `success` flag and handle errors appropriately:

```typescript
const response = await api.catalog.getCategories();
if (!response.success) {
  // Handle error using response.error
}
```
