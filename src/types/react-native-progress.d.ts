declare module 'react-native-progress/Bar' {
  import { Component } from 'react';
  import { ViewStyle } from 'react-native';

  interface ProgressBarProps {
    progress?: number;
    width?: number | null;
    height?: number;
    borderRadius?: number;
    borderWidth?: number;
    color?: string;
    style?: ViewStyle;
  }

  export default class Bar extends Component<ProgressBarProps> {}
} 

declare module 'react-native-progress/Pie';
declare module 'react-native-progress/Circle';
declare module 'react-native-progress/CircleSnail';

declare module 'expo-barcode-generator'; 