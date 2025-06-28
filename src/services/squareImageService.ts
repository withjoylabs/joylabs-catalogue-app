import logger from '../utils/logger';
import { directSquareApi } from '../api';
import * as FileSystem from 'expo-file-system';
import { v4 as uuidv4 } from 'uuid';
import { getDatabase } from '../database/modernDb';
import tokenService from '../services/tokenService';
import { imageService } from '../services/imageService';

export interface SquareImageUploadResult {
  success: boolean;
  imageId?: string;
  imageUrl?: string;
  error?: string;
}

export interface SquareImageDeleteResult {
  success: boolean;
  error?: string;
}

/**
 * Service for managing Square catalog images
 * Handles upload, update, and delete operations with Square API
 */
interface ImageData {
  id: string;
  name: string;
  url: string;
  squareUrl?: string;
  caption?: string;
  itemId: string;
}

class SquareImageService {
  
  /**
   * Upload a new image with different behavior for existing vs new items
   * - Existing items: Complete CRUD operation immediately
   * - New items: Just return image data for React state (save on item save)
   */
  async uploadImage(
    imageUri: string,
    imageName: string,
    itemId: string
  ): Promise<SquareImageUploadResult> {
    try {
      const isNewItem = itemId === 'new-item-temp' || !itemId;

      logger.info('SquareImageService', 'Starting image upload', {
        imageName,
        itemId,
        isNewItem,
        strategy: isNewItem ? 'defer-until-save' : 'immediate-crud'
      });

      // Generate image ID and placeholder URL
      const imageId = `placeholder-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      const squareImageUrl = `https://placeholder-images.example.com/${imageId}.jpg`;

      if (isNewItem) {
        // NEW ITEMS: Just return image data for React state
        // Actual upload will happen when item is saved
        logger.info('SquareImageService', 'New item - deferring upload until item save', {
          imageId,
          itemId
        });

        return {
          success: true,
          imageId,
          imageUrl: imageUri // Return local URI for immediate display
        };

      } else {
        // EXISTING ITEMS: Complete CRUD operation immediately
        logger.info('SquareImageService', 'Existing item - performing immediate CRUD', {
          imageId,
          itemId
        });

        // Step 1: Create image in Square (upload file)
        logger.info('SquareImageService', 'Step 1: Creating image in Square', {
          imageId,
          itemId
        });

        const squareUploadResult = await this.uploadImageToSquare(imageUri, imageName, imageId, itemId);
        if (!squareUploadResult.success) {
          throw new Error(`Square image creation failed: ${squareUploadResult.error}`);
        }

        const actualSquareImageId = squareUploadResult.imageId!;
        const actualSquareImageUrl = squareUploadResult.imageUrl!;
        logger.info('SquareImageService', 'Step 1 completed: Image created in Square', {
          actualSquareImageId,
          squareImageUrl: actualSquareImageUrl,
          originalUri: imageUri
        });

        // Step 2: Save to local database
        // Note: Image is already attached to item via object_id + is_primary in CreateCatalogImage
        await this.saveImageToDatabase(actualSquareImageId, {
          id: actualSquareImageId,
          name: imageName,
          url: imageUri, // Use local URI for immediate display
          squareUrl: actualSquareImageUrl, // Store actual Square URL
          caption: `Image for item ${itemId}`,
          itemId: itemId
        });

        // Step 3: Associate with item in local database
        await this.associateImageWithItem(actualSquareImageId, itemId);

        // Step 4: Clear image service cache to ensure fresh data is loaded
        imageService.clearCache();
        logger.info('SquareImageService', 'Image service cache cleared');

        logger.info('SquareImageService', 'Complete CRUD operation successful', {
          actualSquareImageId,
          itemId,
          localUri: imageUri,
          squareUrl: actualSquareImageUrl
        });

        return {
          success: true,
          imageId: actualSquareImageId,
          imageUrl: imageUri // Return local URI for immediate display
        };
      }

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('SquareImageService', 'Image upload failed', {
        error: errorMessage,
        imageName,
        itemId,
        fullError: error
      });
      return {
        success: false,
        error: errorMessage
      };
    }
  }

  /**
   * Update an existing image in Square
   */
  async updateImage(
    imageId: string,
    newImageUri: string,
    newImageName: string
  ): Promise<SquareImageUploadResult> {
    try {
      logger.info('SquareImageService', 'Starting image update', { imageId, newImageName });

      // 1. Upload the new image file to replace the existing one
      const uploadResult = await this.uploadImageFile(imageId, newImageUri);
      
      if (!uploadResult.success) {
        throw new Error(`Failed to upload new image file: ${uploadResult.error}`);
      }

      // 2. Update the image metadata if name changed
      if (newImageName) {
        await this.updateImageMetadata(imageId, newImageName);
      }

      logger.info('SquareImageService', 'Image update completed successfully', {
        imageId,
        imageUrl: uploadResult.imageUrl
      });

      return {
        success: true,
        imageId,
        imageUrl: uploadResult.imageUrl
      };

    } catch (error) {
      logger.error('SquareImageService', 'Image update failed', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }

  /**
   * Delete an image from Square and remove it from the item
   */
  async deleteImage(imageId: string, itemId?: string): Promise<SquareImageDeleteResult> {
    try {
      logger.info('SquareImageService', 'Starting image deletion', { imageId, itemId });

      // 1. Remove image from item if itemId provided
      if (itemId) {
        await this.removeImageFromItem(itemId, imageId);
      }

      // 2. Delete the image object from Square
      const deleteResponse = await directSquareApi.deleteCatalogObject(imageId);
      
      if (!deleteResponse.success) {
        throw new Error(`Failed to delete image: ${deleteResponse.error?.message || 'Unknown error'}`);
      }

      logger.info('SquareImageService', 'Image deletion completed successfully', { imageId });

      return { success: true };

    } catch (error) {
      logger.error('SquareImageService', 'Image deletion failed', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }

  /**
   * Upload image file to Square using the CreateCatalogImage endpoint
   */
  private async uploadImageToSquare(imageUri: string, imageName: string, imageId: string, itemId: string): Promise<{ success: boolean; imageId?: string; imageUrl?: string; error?: string }> {
    try {
      logger.info('SquareImageService', 'Starting Square CreateCatalogImage API call', { imageId, imageUri });

      // Read the image file
      const fileInfo = await FileSystem.getInfoAsync(imageUri);
      if (!fileInfo.exists) {
        throw new Error('Image file does not exist');
      }

      // Use FileSystem.uploadAsync for proper multipart upload
      const authHeaders = await tokenService.getAuthHeaders();

      // JSON part with image metadata - Upload AND attach in one call
      const imageRequest = {
        idempotency_key: uuidv4(),
        object_id: itemId, // Attach to item immediately
        image: {
          id: "#TEMP_ID", // Square expects this for new images
          type: 'IMAGE',
          image_data: {
            name: imageName,
            caption: `Uploaded via JoyLabs app`
          }
        },
        is_primary: true // Make this the primary image
      };

      logger.info('SquareImageService', 'Using FileSystem.uploadAsync for multipart upload', {
        imageUri,
        imageName,
        requestData: imageRequest
      });

      const squareResponse = await FileSystem.uploadAsync(
        'https://connect.squareup.com/v2/catalog/images',
        imageUri,
        {
          httpMethod: 'POST',
          uploadType: FileSystem.FileSystemUploadType.MULTIPART,
          fieldName: 'file',
          headers: {
            ...authHeaders,
            'Square-Version': '2025-04-16',
          },
          parameters: {
            request: JSON.stringify(imageRequest)
          }
        }
      );

      if (squareResponse.status !== 200) {
        throw new Error(`Square API error: ${squareResponse.status} ${squareResponse.body}`);
      }

      const result = JSON.parse(squareResponse.body);

      if (!result.image || !result.image.image_data) {
        throw new Error('Invalid response from Square CreateCatalogImage API');
      }

      const actualImageId = result.image.id;
      const squareImageUrl = result.image.image_data.url;

      logger.info('SquareImageService', 'Square CreateCatalogImage successful', {
        actualImageId,
        squareImageUrl,
        placeholderImageId: imageId
      });

      return {
        success: true,
        imageId: actualImageId, // Return the actual Square-generated image ID
        imageUrl: squareImageUrl
      };

    } catch (error) {
      logger.error('SquareImageService', 'Square CreateCatalogImage failed', { error, imageId });
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }

  /**
   * Add an image to a Square item's image_ids array
   */
  async addImageToSquareItem(imageId: string, itemId: string): Promise<void> {
    try {
      // 1. Retrieve the current item
      const itemResponse = await directSquareApi.retrieveCatalogObject(itemId, false);
      
      if (!itemResponse.success || !itemResponse.data?.object) {
        throw new Error('Failed to retrieve item for image association');
      }

      const item = itemResponse.data.object;
      const currentImageIds = item.item_data?.image_ids || [];
      
      // 2. Add the new image ID if not already present
      if (!currentImageIds.includes(imageId)) {
        const updatedItem = {
          ...item,
          item_data: {
            ...item.item_data,
            image_ids: [...currentImageIds, imageId]
          }
        };

        // 3. Update the item
        const updateResponse = await directSquareApi.upsertCatalogObject(
          updatedItem,
          uuidv4() // idempotency key
        );

        if (!updateResponse.success) {
          throw new Error('Failed to update item with new image');
        }

        logger.info('SquareImageService', 'Successfully added image to Square item', {
          itemId,
          imageId,
          totalImages: updatedItem.item_data.image_ids.length
        });
      }

    } catch (error) {
      logger.error('SquareImageService', 'Failed to add image to Square item', { error, itemId, imageId });
      throw error;
    }
  }

  /**
   * Remove an image from an item's image_ids array
   */
  private async removeImageFromItem(itemId: string, imageId: string): Promise<void> {
    try {
      // 1. Retrieve the current item
      const itemResponse = await directSquareApi.retrieveCatalogObject(itemId, false);
      
      if (!itemResponse.success || !itemResponse.data?.object) {
        throw new Error('Failed to retrieve item for image removal');
      }

      const item = itemResponse.data.object;
      const currentImageIds = item.item_data?.image_ids || [];
      
      // 2. Remove the image ID
      const updatedImageIds = currentImageIds.filter((id: string) => id !== imageId);
      
      if (updatedImageIds.length !== currentImageIds.length) {
        const updatedItem = {
          ...item,
          item_data: {
            ...item.item_data,
            image_ids: updatedImageIds
          }
        };

        // 3. Update the item
        const updateResponse = await directSquareApi.upsertCatalogObject(
          updatedItem,
          uuidv4() // idempotency key
        );

        if (!updateResponse.success) {
          throw new Error('Failed to update item after image removal');
        }

        logger.info('SquareImageService', 'Successfully removed image from item', { itemId, imageId });
      }

    } catch (error) {
      logger.error('SquareImageService', 'Failed to remove image from item', error);
      throw error;
    }
  }

  /**
   * Update image metadata (name, caption)
   */
  private async updateImageMetadata(imageId: string, newName: string): Promise<void> {
    try {
      // 1. Retrieve the current image object
      const imageResponse = await directSquareApi.retrieveCatalogObject(imageId, false);
      
      if (!imageResponse.success || !imageResponse.data?.object) {
        throw new Error('Failed to retrieve image for metadata update');
      }

      const image = imageResponse.data.object;
      
      // 2. Update the metadata
      const updatedImage = {
        ...image,
        image_data: {
          ...image.image_data,
          name: newName,
          caption: `Image for ${newName}`
        }
      };

      // 3. Update the image object
      const updateResponse = await directSquareApi.upsertCatalogObject(
        updatedImage,
        uuidv4() // idempotency key
      );

      if (!updateResponse.success) {
        throw new Error('Failed to update image metadata');
      }

      logger.info('SquareImageService', 'Successfully updated image metadata', { imageId, newName });

    } catch (error) {
      logger.error('SquareImageService', 'Failed to update image metadata', error);
      throw error;
    }
  }

  /**
   * Save image data to local database
   */
  private async saveImageToDatabase(imageId: string, imageData: ImageData): Promise<void> {
    try {
      logger.info('SquareImageService', 'Saving image to local database', { imageId, itemId: imageData.itemId });

      const db = await getDatabase();

      // Save to images table
      await db.runAsync(
        `INSERT OR REPLACE INTO images
         (id, updated_at, version, is_deleted, name, url, caption, type, data_json)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          imageId,
          new Date().toISOString(),
          '1',
          0,
          imageData.name || '',
          imageData.url || '',
          imageData.caption || '',
          'IMAGE',
          JSON.stringify({
            name: imageData.name,
            url: imageData.url,
            squareUrl: imageData.squareUrl,
            caption: imageData.caption,
            itemId: imageData.itemId
          })
        ]
      );

      logger.info('SquareImageService', 'Image saved to database successfully', { imageId });

      // Verify the save by reading it back
      const verifyResult = await db.getFirstAsync<{ id: string; url: string; name: string }>(
        `SELECT id, url, name FROM images WHERE id = ?`, [imageId]
      );
      logger.info('SquareImageService', 'Database save verification', {
        imageId,
        found: !!verifyResult,
        url: verifyResult?.url,
        name: verifyResult?.name
      });
    } catch (error) {
      logger.error('SquareImageService', 'Failed to save image to database', { error, imageId });
      throw error;
    }
  }

  /**
   * Associate image with item in database
   */
  private async associateImageWithItem(imageId: string, itemId: string): Promise<void> {
    try {
      logger.info('SquareImageService', 'Associating image with item', { imageId, itemId });

      const db = await getDatabase();

      // Get current item data
      const itemResult = await db.getFirstAsync<{
        id: string;
        data_json: string;
      }>(`SELECT id, data_json FROM catalog_items WHERE id = ?`, [itemId]);

      if (itemResult) {
        const currentData = itemResult.data_json ? JSON.parse(itemResult.data_json) : {};
        const currentImageIds = currentData.image_ids || [];

        // Add the new image ID if not already present
        if (!currentImageIds.includes(imageId)) {
          const updatedData = {
            ...currentData,
            image_ids: [...currentImageIds, imageId]
          };

          // Update the item with new image_ids
          await db.runAsync(
            `UPDATE catalog_items SET data_json = ?, updated_at = ? WHERE id = ?`,
            [JSON.stringify(updatedData), new Date().toISOString(), itemId]
          );

          logger.info('SquareImageService', 'Image associated with item successfully', {
            itemId,
            imageId,
            totalImages: updatedData.image_ids.length
          });

          // Verify the association by reading it back
          const verifyResult = await db.getFirstAsync<{ id: string; data_json: string }>(
            `SELECT id, data_json FROM catalog_items WHERE id = ?`, [itemId]
          );
          if (verifyResult) {
            const verifyData = JSON.parse(verifyResult.data_json || '{}');
            logger.info('SquareImageService', 'Item association verification', {
              itemId,
              imageId,
              currentImageIds: verifyData.image_ids || [],
              imageFound: (verifyData.image_ids || []).includes(imageId)
            });
          }
        } else {
          logger.info('SquareImageService', 'Image already associated with item', { itemId, imageId });
        }
      } else {
        logger.warn('SquareImageService', 'Item not found in database', { itemId });
        throw new Error(`Item ${itemId} not found in database`);
      }
    } catch (error) {
      logger.error('SquareImageService', 'Failed to associate image with item', { error, imageId, itemId });
      throw error;
    }
  }


}

// Export singleton instance
export const squareImageService = new SquareImageService();
export default squareImageService;
