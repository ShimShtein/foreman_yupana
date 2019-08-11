/* eslint import/no-unresolved: [2, { ignore: [foremanReact/*] }] */
/* eslint-disable import/no-extraneous-dependencies */
/* eslint-disable import/extensions */
import componentRegistry from 'foremanReact/components/componentRegistry';
import { registerReducer } from 'foremanReact/common/MountingService';
import reducers from './InventoryUpload/InventoryUploadReducers';
import InventoryUpload from './InventoryUpload';

// register reducers
Object.entries(reducers).forEach(([key, reducer]) =>
  registerReducer(key, reducer)
);

// register components
componentRegistry.register({
  name: 'InventoryUpload',
  type: InventoryUpload,
});
