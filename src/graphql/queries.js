/* eslint-disable */
// this is an auto generated file. This will be overwritten

export const getItemData = /* GraphQL */ `
  query GetItemData($id: ID!) {
    getItemData(id: $id) {
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
export const listItemData = /* GraphQL */ `
  query ListItemData(
    $filter: ModelItemDataFilterInput
    $limit: Int
    $nextToken: String
  ) {
    listItemData(filter: $filter, limit: $limit, nextToken: $nextToken) {
      items {
        id
        caseUpc
        caseCost
        caseQuantity
        vendor
        discontinued
        createdAt
        updatedAt
        owner
        __typename
      }
      nextToken
      __typename
    }
  }
`;
export const getItemChangeLog = /* GraphQL */ `
  query GetItemChangeLog($id: ID!) {
    getItemChangeLog(id: $id) {
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
export const listItemChangeLogs = /* GraphQL */ `
  query ListItemChangeLogs(
    $filter: ModelItemChangeLogFilterInput
    $limit: Int
    $nextToken: String
  ) {
    listItemChangeLogs(filter: $filter, limit: $limit, nextToken: $nextToken) {
      items {
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
      nextToken
      __typename
    }
  }
`;
export const getReorderItem = /* GraphQL */ `
  query GetReorderItem($id: ID!) {
    getReorderItem(id: $id) {
      id
      itemId
      itemName
      itemBarcode
      itemCategory
      itemPrice
      quantity
      completed
      received
      addedBy
      createdAt
      updatedAt
      owner
      __typename
    }
  }
`;
export const listReorderItems = /* GraphQL */ `
  query ListReorderItems(
    $filter: ModelReorderItemFilterInput
    $limit: Int
    $nextToken: String
  ) {
    listReorderItems(filter: $filter, limit: $limit, nextToken: $nextToken) {
      items {
        id
        itemId
        itemName
        itemBarcode
        itemCategory
        itemPrice
        quantity
        completed
        received
        addedBy
        createdAt
        updatedAt
        owner
        __typename
      }
      nextToken
      __typename
    }
  }
`;
export const itemsByCaseUpc = /* GraphQL */ `
  query ItemsByCaseUpc(
    $caseUpc: String!
    $sortDirection: ModelSortDirection
    $filter: ModelItemDataFilterInput
    $limit: Int
    $nextToken: String
  ) {
    itemsByCaseUpc(
      caseUpc: $caseUpc
      sortDirection: $sortDirection
      filter: $filter
      limit: $limit
      nextToken: $nextToken
    ) {
      items {
        id
        caseUpc
        caseCost
        caseQuantity
        vendor
        discontinued
        createdAt
        updatedAt
        owner
        __typename
      }
      nextToken
      __typename
    }
  }
`;
export const listChangesForItem = /* GraphQL */ `
  query ListChangesForItem(
    $itemID: ID!
    $sortDirection: ModelSortDirection
    $filter: ModelItemChangeLogFilterInput
    $limit: Int
    $nextToken: String
  ) {
    listChangesForItem(
      itemID: $itemID
      sortDirection: $sortDirection
      filter: $filter
      limit: $limit
      nextToken: $nextToken
    ) {
      items {
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
      nextToken
      __typename
    }
  }
`;
export const reordersByItemId = /* GraphQL */ `
  query ReordersByItemId(
    $itemId: ID!
    $sortDirection: ModelSortDirection
    $filter: ModelReorderItemFilterInput
    $limit: Int
    $nextToken: String
  ) {
    reordersByItemId(
      itemId: $itemId
      sortDirection: $sortDirection
      filter: $filter
      limit: $limit
      nextToken: $nextToken
    ) {
      items {
        id
        itemId
        itemName
        itemBarcode
        itemCategory
        itemPrice
        quantity
        completed
        addedBy
        createdAt
        updatedAt
        owner
        __typename
      }
      nextToken
      __typename
    }
  }
`;
