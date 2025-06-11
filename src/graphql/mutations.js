/* eslint-disable */
// this is an auto generated file. This will be overwritten

export const createItemData = /* GraphQL */ `
  mutation CreateItemData(
    $input: CreateItemDataInput!
    $condition: ModelItemDataConditionInput
  ) {
    createItemData(input: $input, condition: $condition) {
      id
      caseUpc
      caseCost
      caseQuantity
      vendor
      discontinued
      notes {
        id
        content
        isComplete
        authorId
        authorName
        createdAt
        updatedAt
        __typename
      }
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
export const updateItemData = /* GraphQL */ `
  mutation UpdateItemData(
    $input: UpdateItemDataInput!
    $condition: ModelItemDataConditionInput
  ) {
    updateItemData(input: $input, condition: $condition) {
      id
      caseUpc
      caseCost
      caseQuantity
      vendor
      discontinued
      notes {
        id
        content
        isComplete
        authorId
        authorName
        createdAt
        updatedAt
        __typename
      }
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
export const deleteItemData = /* GraphQL */ `
  mutation DeleteItemData(
    $input: DeleteItemDataInput!
    $condition: ModelItemDataConditionInput
  ) {
    deleteItemData(input: $input, condition: $condition) {
      id
      caseUpc
      caseCost
      caseQuantity
      vendor
      discontinued
      notes {
        id
        content
        isComplete
        authorId
        authorName
        createdAt
        updatedAt
        __typename
      }
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
export const createItemChangeLog = /* GraphQL */ `
  mutation CreateItemChangeLog(
    $input: CreateItemChangeLogInput!
    $condition: ModelItemChangeLogConditionInput
  ) {
    createItemChangeLog(input: $input, condition: $condition) {
      id
      itemID
      authorId
      authorName
      timestamp
      changeType
      changeDetails
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
export const updateItemChangeLog = /* GraphQL */ `
  mutation UpdateItemChangeLog(
    $input: UpdateItemChangeLogInput!
    $condition: ModelItemChangeLogConditionInput
  ) {
    updateItemChangeLog(input: $input, condition: $condition) {
      id
      itemID
      authorId
      authorName
      timestamp
      changeType
      changeDetails
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
export const deleteItemChangeLog = /* GraphQL */ `
  mutation DeleteItemChangeLog(
    $input: DeleteItemChangeLogInput!
    $condition: ModelItemChangeLogConditionInput
  ) {
    deleteItemChangeLog(input: $input, condition: $condition) {
      id
      itemID
      authorId
      authorName
      timestamp
      changeType
      changeDetails
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
