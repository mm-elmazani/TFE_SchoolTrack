import { apiClient } from '@/api/axios';

export interface Class {
  id: string;
  name: string;
  year: string | null;
  nb_students: number;
  nb_teachers: number;
  created_at: string;
  updated_at: string;
}

export const classApi = {
  getAll: async (): Promise<Class[]> => {
    const response = await apiClient.get('/api/v1/classes');
    return response.data;
  },

  getById: async (id: string): Promise<Class> => {
    const response = await apiClient.get(`/api/v1/classes/${id}`);
    return response.data;
  },

  create: async (data: { name: string; year?: string }): Promise<Class> => {
    const response = await apiClient.post('/api/v1/classes', data);
    return response.data;
  },

  update: async (id: string, data: { name?: string; year?: string }): Promise<Class> => {
    const response = await apiClient.put(`/api/v1/classes/${id}`, data);
    return response.data;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/v1/classes/${id}`);
  },

  getStudents: async (id: string): Promise<string[]> => {
    const response = await apiClient.get(`/api/v1/classes/${id}/students`);
    return response.data;
  },

  assignStudents: async (id: string, student_ids: string[]): Promise<Class> => {
    const response = await apiClient.post(`/api/v1/classes/${id}/students`, { student_ids });
    return response.data;
  },

  removeStudent: async (classId: string, studentId: string): Promise<void> => {
    await apiClient.delete(`/api/v1/classes/${classId}/students/${studentId}`);
  },
};

