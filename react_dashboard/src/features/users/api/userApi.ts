import { apiClient } from '@/api/axios';

export interface User {
  id: string;
  email: string;
  first_name: string | null;
  last_name: string | null;
  role: string;
  is_2fa_enabled: boolean;
}

export const userApi = {
  getAll: async (): Promise<User[]> => {
    const response = await apiClient.get('/api/v1/users');
    return response.data;
  },

  create: async (data: any): Promise<User> => {
    const response = await apiClient.post('/api/v1/users', data);
    return response.data;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/v1/users/${id}`);
  },
};
