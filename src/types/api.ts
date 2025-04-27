// Square API Response Types

// Base Response Type
export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: ApiError;
}

export interface ApiError {
  code: string;
  message: string;
  details?: Record<string, any>;
}

// Pagination
export interface PaginationCursor {
  cursor: string | null;
}

// Authentication
export interface AuthTokenResponse {
  access_token: string;
  token_type: string;
  expires_at: string;
  merchant_id: string;
  refresh_token?: string;
}

// Catalog Types
export interface CatalogObject {
  id: string;
  type: string;
  updated_at: string;
  created_at: string;
  version: number;
  is_deleted: boolean;
  present_at_all_locations: boolean;
  present_at_location_ids?: string[];
  absent_at_location_ids?: string[];
  [key: string]: any; // For item_data, category_data, etc.
}

export interface CatalogItemData {
  name: string;
  description?: string;
  abbreviation?: string;
  label_color?: string;
  available_online?: boolean;
  available_for_pickup?: boolean;
  available_electronically?: boolean;
  category_id?: string;
  tax_ids?: string[];
  variations?: CatalogObject[];
  product_type?: 'REGULAR' | 'GIFT_CARD' | 'APPOINTMENTS_SERVICE';
  skip_modifier_screen?: boolean;
  item_options?: CatalogObject[];
  image_ids?: string[];
  sort_name?: string;
  categories?: { id: string; name: string }[];
  description_html?: string;
  description_plaintext?: string;
}

export interface CatalogCategoryData {
  name: string;
  image_ids?: string[];
  category_type?: string;
}

export interface CatalogImage {
  id: string;
  type: string;
  image_data: {
    url: string;
    caption?: string;
  };
}

export interface CatalogItemsResponse extends PaginationCursor {
  items: CatalogObject[];
}

// Converted types that match our frontend store
export interface ConvertedItem {
  id: string;
  version?: number;
  variationId?: string;
  variationVersion?: number;
  name: string;
  sku: string | null;
  abbreviation?: string;
  price?: number;
  description?: string;
  category?: string;
  categoryId?: string;
  reporting_category_id?: string;
  isActive: boolean;
  images: { id: string; url: string; name: string }[];
  taxIds?: string[];
  modifierListIds?: string[];
  updatedAt?: string;
  createdAt?: string;
  barcode?: string;
  stock?: number;
  variationName?: string | null | undefined;
  variations?: Array<{
    id?: string;
    version?: number;
    name: string;
    sku: string | null;
    price?: number;
    barcode?: string;
  }>;
}

export interface ConvertedCategory {
  id: string;
  name: string;
  description?: string;
  color: string;
  icon?: string;
  isActive: boolean;
  parentCategory?: string;
  itemCount?: number;
  createdAt: string;
  updatedAt: string;
}

// Webhook Types
export interface WebhookData {
  id: string;
  event_type: string;
  created_at: number;
  merchant_id: string;
  data: {
    type: string;
    id: string;
    object: Record<string, any>;
  };
}

// Error Responses
export interface ErrorResponse {
  success: false;
  error: {
    code: string;
    message: string;
    details?: Record<string, any>;
  };
} 