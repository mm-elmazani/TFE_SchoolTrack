import { apiClient } from '@/api/axios';

export interface Student {
  id: string;
  first_name: string;
  last_name: string;
  email: string | null;
  qr_code_hash: string | null;
  is_deleted: boolean;
  created_at: string;
}

export const studentApi = {
  getAll: async (): Promise<Student[]> => {
    const response = await apiClient.get('/api/v1/students');
    return response.data;
  },

  create: async (data: { first_name: string; last_name: string; email?: string; class_id?: string }): Promise<Student> => {
    const response = await apiClient.post('/api/v1/students', data);
    return response.data;
  },

  uploadCsv: async (file: File) => {
    const formData = new FormData();
    formData.append('file', file);
    const response = await apiClient.post('/api/v1/students/upload', formData, {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
    });
    return response.data;
  },

  update: async (id: string, data: { first_name?: string; last_name?: string; email?: string }): Promise<Student> => {
    const response = await apiClient.put(`/api/v1/students/${id}`, data);
    return response.data;
  },

  delete: async (id: string): Promise<void> => {
    await apiClient.delete(`/api/v1/students/${id}`);
  },

  getGdprExport: async (id: string): Promise<any> => {
    const response = await apiClient.get(`/api/v1/students/${id}/data-export`);
    return response.data;
  },
};
