// @ts-check
import { initSchema } from '@aws-amplify/datastore';
import { schema } from './schema';



const { ItemData, ItemChangeLog, Note } = initSchema(schema);

export {
  ItemData,
  ItemChangeLog,
  Note
};