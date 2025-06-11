import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, TextInput, Button, Alert } from 'react-native';
import { fetchUserAttributes, updateUserAttribute } from 'aws-amplify/auth';
import { useRouter } from 'expo-router';

const EditProfileScreen = () => {
  const router = useRouter();
  const [name, setName] = useState('');
  const [title, setTitle] = useState('');

  useEffect(() => {
    const fetchAttributes = async () => {
      try {
        const attributes = await fetchUserAttributes();
        setName(attributes.name || '');
        setTitle(attributes['custom:title'] || '');
      } catch (error) {
        console.error('Error fetching user attributes:', error);
        Alert.alert('Error', 'Could not fetch user profile.');
      }
    };
    fetchAttributes();
  }, []);

  const handleSaveChanges = async () => {
    try {
      await updateUserAttribute({
        userAttribute: {
          attributeKey: 'name',
          value: name,
        },
      });
      await updateUserAttribute({
        userAttribute: {
          attributeKey: 'custom:title',
          value: title,
        },
      });
      Alert.alert('Success', 'Profile updated successfully.');
      router.back();
    } catch (error) {
      console.error('Error updating user attributes:', error);
      Alert.alert('Error', 'Could not update profile.');
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.label}>Name</Text>
      <TextInput
        style={styles.input}
        placeholder="Enter your name"
        value={name}
        onChangeText={setName}
      />
      <Text style={styles.label}>Title</Text>
      <TextInput
        style={styles.input}
        placeholder="Enter your title"
        value={title}
        onChangeText={setTitle}
      />
      <Button title="Update Profile Photo" onPress={() => Alert.alert('Not Implemented', 'Profile photo update is not yet implemented.')} />
      <Button title="Save Changes" onPress={handleSaveChanges} />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
    backgroundColor: '#fff',
  },
  label: {
    fontSize: 16,
    marginBottom: 8,
  },
  input: {
    borderWidth: 1,
    borderColor: '#ccc',
    padding: 8,
    marginBottom: 16,
    borderRadius: 4,
  },
});

export default EditProfileScreen; 