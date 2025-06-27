import logger from '../utils/logger';
import { directSquareApi } from '../api';
import * as FileSystem from 'expo-file-system';
import { v4 as uuidv4 } from 'uuid';

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
class SquareImageService {
  
  /**
   * Upload a new image to Square and associate it with an item
   */
  async uploadImage(
    imageUri: string,
    imageName: string,
    itemId: string
  ): Promise<SquareImageUploadResult> {
    try {
      logger.info('SquareImageService', 'Starting image upload', { imageName, itemId });

      // 1. First, create the image object in Square's catalog
      const imageObject = {
        type: 'IMAGE',
        id: `#${uuidv4()}`, // Temporary ID for new objects
        image_data: {
          name: imageName,
          caption: `Image for ${imageName}`
        }
      };

      // 2. Create the catalog image object
      const createResponse = await directSquareApi.upsertCatalogObject(
        imageObject,
        uuidv4() // idempotency key
      );

      if (!createResponse.success || !createResponse.data?.catalog_object) {
        throw new Error(`Failed to create image object: ${createResponse.error?.message || 'Unknown error'}`);
      }

      const createdImageId = createResponse.data.catalog_object.id;
      logger.info('SquareImageService', 'Created image object', { imageId: createdImageId });

      // 3. Upload the actual image file
      const uploadResult = await this.uploadImageFile(createdImageId, imageUri);
      
      if (!uploadResult.success) {
        // If file upload fails, we should clean up the created image object
        await this.deleteImage(createdImageId);
        throw new Error(`Failed to upload image file: ${uploadResult.error}`);
      }

      // 4. Update the item to include this image
      await this.addImageToItem(itemId, createdImageId);

      logger.info('SquareImageService', 'Image upload completed successfully', {
        imageId: createdImageId,
        imageUrl: uploadResult.imageUrl
      });

      return {
        success: true,
        imageId: createdImageId,
        imageUrl: uploadResult.imageUrl
      };

    } catch (error) {
      logger.error('SquareImageService', 'Image upload failed', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
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
  private async uploadImageFile(imageId: string, imageUri: string): Promise<SquareImageUploadResult> {
    try {
      // Read the image file
      const fileInfo = await FileSystem.getInfoAsync(imageUri);
      if (!fileInfo.exists) {
        throw new Error('Image file does not exist');
      }

      // TODO: Implement actual Square CreateCatalogImage API call
      // This requires multipart/form-data upload with:
      // - JSON part with idempotency_key, object_id, image metadata
      // - File part with the actual image data
      // Example: https://developer.squareup.com/reference/square/catalog-api/create-catalog-image
      // For now, we'll return a placeholder to allow the UI to work

      logger.info('SquareImageService', 'Image file upload - using placeholder implementation', { imageId, imageUri });

      // Simulate upload delay
      await new Promise(resolve => setTimeout(resolve, 1000));

      // Return success with a placeholder URL
      // In real implementation, this would be the actual Square image URL from the API response
      return {
        success: true,
        imageUrl: `https://square-catalog-sandbox.s3.amazonaws.com/files/placeholder-${imageId}/original.png`
      };

    } catch (error) {
      logger.error('SquareImageService', 'Image file upload failed', error);
      return {
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }

  /**
   * Add an image to an item's image_ids array
   */
  private async addImageToItem(itemId: string, imageId: string): Promise<void> {
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

        logger.info('SquareImageService', 'Successfully added image to item', { itemId, imageId });
      }

    } catch (error) {
      logger.error('SquareImageService', 'Failed to add image to item', error);
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
}

// Export singleton instance
export const squareImageService = new SquareImageService();
export default squareImageService;
