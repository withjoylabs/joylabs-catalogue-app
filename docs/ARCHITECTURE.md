# JoyLabs Frontend Architecture

This document outlines the architectural design, data flow, and integration points of the JoyLabs frontend application.

## System Overview

The JoyLabs application follows a client-server architecture:

- **Frontend**: React Native mobile application (this repository)
- **Backend**: AWS Lambda functions exposed through API Gateway
- **Data Source**: Square API for merchant catalog and inventory data

The frontend communicates with the backend through RESTful APIs, and the backend interfaces with Square API for data operations. Authentication is handled through OAuth 2.0 with Square.

## Key Components

### API Client

Located in `src/api/index.ts`, the API client serves as the central interface for all backend communication:

- **Configuration**: Configured with Axios, with base URL set to the production environment
- **Request Interceptors**: Add authentication headers and handle request formatting
- **Response Interceptors**: Process responses, handle errors, and format data for frontend consumption
- **Cache Management**: Implements TTL-based caching for improved performance
- **Error Handling**: Centralized error processing and reporting

### Authentication Service

Located in `src/services/tokenService.ts`, handles:

- Secure storage of authentication tokens using Expo SecureStore
- Token refresh mechanisms
- Connection state verification

### Hooks

Custom hooks provide domain-specific functionality:

- **useCategories** (`src/hooks/useCategories.ts`): Manages category data and operations
- **useApi** (`src/hooks/useApi.ts`): Provides API state and operations to components
- **useItems** (`src/hooks/useItems.ts`): Handles catalog item fetching and caching

### Screens

Key screens include:

- **Profile** (`app/profile.tsx`): Contains merchant profile, connection status, and category management
- **Home** (`app/index.tsx`): Main dashboard for the application
- **Scanner** (`app/scanner.tsx`): Barcode scanning functionality

## Authentication Flow

1. **Initiation**: User initiates Square connection from Profile screen
2. **Authorization Request**: App generates a connection URL using PKCE and opens a web browser
3. **User Consent**: User grants permissions in Square's OAuth page
4. **Callback Processing**: Square redirects to our callback URL with an authorization code
5. **Token Exchange**: Backend exchanges the code for access and refresh tokens
6. **Token Storage**: Tokens are securely stored using Expo SecureStore
7. **State Management**: Connection state is updated in the ApiProvider context

## Data Management

### Categories

- Fetched via `useCategories` hook
- Stored in hook state and available through returned methods
- Can be refreshed selectively using `refreshData('categories')`
- Alphabetically sorted for consistency
- Connected to UI components through context providers

### Catalog Items

- Managed through a similar hook pattern
- Support for pagination and search functionality
- Cached with TTL to reduce API calls

## State Management

- **Component State**: Managed using React's useState and useEffect hooks
- **Application State**: Managed using Zustand store (useStore)
- **API State**: Provided through context providers (ApiProvider)
- **Navigation State**: Managed by React Navigation

## Data Flow

### Category Retrieval Flow

1. User navigates to Profile screen and selects Categories tab
2. `useEffect` in Profile component calls `fetchCategories` from `useCategories` hook
3. Hook checks connection status before proceeding
4. API client makes request to `/v2/catalog/list-categories` endpoint
5. Response is processed, transformed, and stored in hook state
6. UI components re-render with the updated category data

### Authentication Flow

1. User presses "Connect to Square" in Profile screen
2. App requests connection URL from `/api/auth/connect/url`
3. WebBrowser opens the URL for user authorization
4. After authorization, Square redirects to our callback URL
5. Callback handler extracts the authorization code
6. Backend exchanges code for tokens and returns them to the app
7. Tokens are securely stored and connection state is updated

## Performance Optimizations

- **Caching**: TTL-based caching to reduce redundant API calls
- **Selective Refreshing**: Only refresh required data sets
- **Pagination**: Implement pagination for large data sets
- **Offline Capabilities**: Basic functionality works without connectivity
- **Network Handling**: Graceful degradation during network issues

## Error Handling

- **Automatic Retries**: Critical operations retry automatically
- **Token Refresh**: Expired tokens are refreshed automatically
- **User Feedback**: Error state propagation to UI with clear messaging
- **Logging**: Remote logging for critical errors
- **Recovery Flows**: Multiple paths to recover from error states

## Security Considerations

- **Token Storage**: SecureStore for sensitive credential storage
- **HTTPS Communication**: All API communication over secure channels
- **Token Refresh**: Automatic token refresh before expiration
- **Connection Verification**: Verify connection status before sensitive operations

## Recent Updates

- Categories endpoint migrated to use `/v2/catalog/list-categories` for improved performance
- UI improvements for category management
- Enhanced error handling for API failures
- Added TTL-based caching for API responses

## Development Guidelines

- Test OAuth flow using Expo deep linking - no custom URL schemes
- Always use production mode for API requests
- Check all dependencies when making changes to authentication or API flows
- Square redirect URL must use HTTPS: `https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/auth/square/callback`
