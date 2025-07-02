/* eslint-disable */
// this is an auto generated file. This will be overwritten

export const onCreateItemData = /* GraphQL */ `
  subscription OnCreateItemData(
    $filter: ModelSubscriptionItemDataFilterInput
    $owner: String
  ) {
    onCreateItemData(filter: $filter, owner: $owner) {
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
export const onUpdateItemData = /* GraphQL */ `
  subscription OnUpdateItemData(
    $filter: ModelSubscriptionItemDataFilterInput
    $owner: String
  ) {
    onUpdateItemData(filter: $filter, owner: $owner) {
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
export const onDeleteItemData = /* GraphQL */ `
  subscription OnDeleteItemData(
    $filter: ModelSubscriptionItemDataFilterInput
    $owner: String
  ) {
    onDeleteItemData(filter: $filter, owner: $owner) {
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
export const onCreateItemChangeLog = /* GraphQL */ `
  subscription OnCreateItemChangeLog(
    $filter: ModelSubscriptionItemChangeLogFilterInput
    $owner: String
  ) {
    onCreateItemChangeLog(filter: $filter, owner: $owner) {
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
export const onUpdateItemChangeLog = /* GraphQL */ `
  subscription OnUpdateItemChangeLog(
    $filter: ModelSubscriptionItemChangeLogFilterInput
    $owner: String
  ) {
    onUpdateItemChangeLog(filter: $filter, owner: $owner) {
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
export const onDeleteItemChangeLog = /* GraphQL */ `
  subscription OnDeleteItemChangeLog(
    $filter: ModelSubscriptionItemChangeLogFilterInput
    $owner: String
  ) {
    onDeleteItemChangeLog(filter: $filter, owner: $owner) {
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
export const onCreateReorderItem = /* GraphQL */ `
  subscription OnCreateReorderItem(
    $filter: ModelSubscriptionReorderItemFilterInput
    $owner: String
  ) {
    onCreateReorderItem(filter: $filter, owner: $owner) {
      id
      itemId
      quantity
      status
      addedBy
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
export const onUpdateReorderItem = /* GraphQL */ `
  subscription OnUpdateReorderItem(
    $filter: ModelSubscriptionReorderItemFilterInput
    $owner: String
  ) {
    onUpdateReorderItem(filter: $filter, owner: $owner) {
      id
      itemId
      quantity
      status
      addedBy
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
export const onDeleteReorderItem = /* GraphQL */ `
  subscription OnDeleteReorderItem(
    $filter: ModelSubscriptionReorderItemFilterInput
    $owner: String
  ) {
    onDeleteReorderItem(filter: $filter, owner: $owner) {
      id
      itemId
      quantity
      status
      addedBy
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
