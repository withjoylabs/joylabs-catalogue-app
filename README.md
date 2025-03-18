# JoyLabs

A modular React Native application built with Expo SDK 52 and TypeScript.

## Features

- Modern React Native application using Expo SDK 52
- File-based routing with Expo Router
- TypeScript for type safety
- Modular architecture for scalability
- Theme system with light and dark mode support
- Reusable UI components

## Project Structure

```
joylabs/
├── app/                  # Expo Router pages
│   ├── _layout.tsx       # Root layout
│   ├── index.tsx         # Home screen
│   ├── modules.tsx       # Modules listing screen
│   └── profile.tsx       # Profile screen
├── src/                  # Source code
│   ├── components/       # Reusable UI components
│   ├── hooks/            # Custom React hooks
│   ├── navigation/       # Navigation related code
│   ├── screens/          # Screen components
│   ├── services/         # API services
│   ├── themes/           # Theme definitions
│   ├── types/            # TypeScript type definitions
│   └── utils/            # Utility functions
├── assets/               # Static assets
```

## Installation

1. Clone the repository
2. Install dependencies:

```bash
npm install
```

## Running the App

```bash
# Start the development server
npm start

# Run on iOS
npm run ios

# Run on Android
npm run android

# Run on Web
npm run web
```

## Adding New Modules

To add a new module to the app:

1. Define the module interface in `src/types/index.ts`
2. Create components in `src/components/`
3. Create a screen in the `app/` directory
4. Add the module to the modules list in `app/modules.tsx`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 