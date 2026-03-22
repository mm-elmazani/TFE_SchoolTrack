import { apiClient } from '@/api/axios';

export interface ClassSummary {
  id: string;
  name: string;
  student_count: number;
  year: string | null;
}

export interface Trip {
  id: string;
  destination: string;
  date: string;
  description: string | null;
  status: 'PLANNED' | 'ACTIVE' | 'COMPLETED' | 'ARCHIVED';
  total_students: number;
  classes: ClassSummary[];
  created_at: string;
  updated_at: string;
}

export const tripApi = {
  getAll: async (): Promise<Trip[]> => {
    const response = await apiClient.get('/api/v1/trips');
    return response.data;
  },

  getById: async (id: string): Promise<Trip> => {
    const response = await apiClient.get(`/api/v1/trips/${id}`);
    return response.data;
  },

  create: async (data: { destination: string; date: string; description?: string; class_ids: string[] }): Promise<Trip> => {
    const response = await apiClient.post('/api/v1/trips', data);
    return response.data;
  },

  update: async (id: string, data: { destination?: string; date?: string; description?: string; status?: string; class_ids?: string[] }): Promise<Trip> => {
    const response = await apiClient.put(`/api/v1/trips/${id}`, data);
    return response.data;
  },

  archive: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/v1/trips/${id}`);
  },
};
