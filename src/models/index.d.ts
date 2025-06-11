import { ModelInit, MutableModel, __modelMeta__, ManagedIdentifier } from "@aws-amplify/datastore";
// @ts-ignore
import { LazyLoading, LazyLoadingDisabled } from "@aws-amplify/datastore";



type EagerNote = {
  readonly id: string;
  readonly content: string;
  readonly isComplete: boolean;
  readonly authorId: string;
  readonly authorName: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}

type LazyNote = {
  readonly id: string;
  readonly content: string;
  readonly isComplete: boolean;
  readonly authorId: string;
  readonly authorName: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export declare type Note = LazyLoading extends LazyLoadingDisabled ? EagerNote : LazyNote

export declare const Note: (new (init: ModelInit<Note>) => Note)

type EagerItemData = {
  readonly [__modelMeta__]: {
    identifier: ManagedIdentifier<ItemData, 'id'>;
    readOnlyFields: 'createdAt' | 'updatedAt';
  };
  readonly id: string;
  readonly caseUpc?: string | null;
  readonly caseCost?: number | null;
  readonly caseQuantity?: number | null;
  readonly vendor?: string | null;
  readonly discontinued?: boolean | null;
  readonly notes?: (Note | null)[] | null;
  readonly createdAt?: string | null;
  readonly updatedAt?: string | null;
}

type LazyItemData = {
  readonly [__modelMeta__]: {
    identifier: ManagedIdentifier<ItemData, 'id'>;
    readOnlyFields: 'createdAt' | 'updatedAt';
  };
  readonly id: string;
  readonly caseUpc?: string | null;
  readonly caseCost?: number | null;
  readonly caseQuantity?: number | null;
  readonly vendor?: string | null;
  readonly discontinued?: boolean | null;
  readonly notes?: (Note | null)[] | null;
  readonly createdAt?: string | null;
  readonly updatedAt?: string | null;
}

export declare type ItemData = LazyLoading extends LazyLoadingDisabled ? EagerItemData : LazyItemData

export declare const ItemData: (new (init: ModelInit<ItemData>) => ItemData) & {
  copyOf(source: ItemData, mutator: (draft: MutableModel<ItemData>) => MutableModel<ItemData> | void): ItemData;
}

type EagerItemChangeLog = {
  readonly [__modelMeta__]: {
    identifier: ManagedIdentifier<ItemChangeLog, 'id'>;
    readOnlyFields: 'createdAt' | 'updatedAt';
  };
  readonly id: string;
  readonly itemID: string;
  readonly authorId: string;
  readonly authorName: string;
  readonly timestamp: string;
  readonly changeType: string;
  readonly changeDetails: string;
  readonly createdAt?: string | null;
  readonly updatedAt?: string | null;
}

type LazyItemChangeLog = {
  readonly [__modelMeta__]: {
    identifier: ManagedIdentifier<ItemChangeLog, 'id'>;
    readOnlyFields: 'createdAt' | 'updatedAt';
  };
  readonly id: string;
  readonly itemID: string;
  readonly authorId: string;
  readonly authorName: string;
  readonly timestamp: string;
  readonly changeType: string;
  readonly changeDetails: string;
  readonly createdAt?: string | null;
  readonly updatedAt?: string | null;
}

export declare type ItemChangeLog = LazyLoading extends LazyLoadingDisabled ? EagerItemChangeLog : LazyItemChangeLog

export declare const ItemChangeLog: (new (init: ModelInit<ItemChangeLog>) => ItemChangeLog) & {
  copyOf(source: ItemChangeLog, mutator: (draft: MutableModel<ItemChangeLog>) => MutableModel<ItemChangeLog> | void): ItemChangeLog;
}