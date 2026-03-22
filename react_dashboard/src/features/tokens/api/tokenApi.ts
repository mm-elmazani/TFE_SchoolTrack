import { apiClient } from '@/api/axios';

export interface TokenAssignment {
  id: string;
  student_id: string;
  trip_id: string;
  token_uid: string;
  assignment_type: 'NFC_PHYSICAL' | 'QR_PHYSICAL' | 'QR_DIGITAL';
  assigned_at: string;
  released_at: string | null;
}

export interface TripStudentInfo {
  id: string;
  first_name: string;
  last_name: string;
  is_assigned: boolean;
  token_uid: string | null;
  assignment_type: 'NFC_PHYSICAL' | 'QR_PHYSICAL' | 'QR_DIGITAL' | null;
  assigned_at: string | null;
}

export interface TripStudentsResponse {
  trip_id: string;
  students: TripStudentInfo[];
  total: number;
  assigned: number;
  unassigned: number;
}

export interface TripAssignmentStatus {
  total_students: number;
  assigned_tokens: number;
  remaining_students: number;
}

export interface QrEmailResult {
  sent_count: number;
  errors: string[];
}

export const tokenApi = {
  getTripAssignmentsStatus: async (tripId: string): Promise<TripAssignmentStatus> => {
    const response = await apiClient.get(`/api/v1/trips/${tripId}/assignments`);
    return response.data;
  },

  getTripStudents: async (tripId: string): Promise<TripStudentsResponse> => {
    const response = await apiClient.get(`/api/v1/trips/${tripId}/students`);
    return response.data;
  },

  assignToken: async (data: { trip_id: string, student_id: string, token_uid: string, assignment_type: string }): Promise<any> => {
    const response = await apiClient.post('/api/v1/tokens/assign', data);
    return response.data;
  },

  reassignToken: async (data: { trip_id: string, student_id: string, token_uid: string, assignment_type: string, justification?: string }): Promise<any> => {
    const response = await apiClient.post('/api/v1/tokens/reassign', data);
    return response.data;
  },

  releaseTripTokens: async (tripId: string): Promise<{ trip_id: string, released_count: number }> => {
    const response = await apiClient.post(`/api/v1/trips/${tripId}/release-tokens`);
    return response.data;
  },

  sendQrEmails: async (tripId: string): Promise<QrEmailResult> => {
    const response = await apiClient.post(`/api/v1/trips/${tripId}/send-qr-emails`);
    return response.data;
  },

  getExportUrl: (tripId: string, password?: string) => {
    const baseUrl = import.meta.env.VITE_API_URL || '';
    let url = `${baseUrl}/api/v1/trips/${tripId}/assignments/export`;
    if (password) {
      url += `?password=${encodeURIComponent(password)}`;
    }
    return url;
  },

  getAllTokens: async (params?: { status?: string, token_type?: string }): Promise<any[]> => {
    const response = await apiClient.get('/api/v1/tokens', { params });
    return response.data;
  },

  getTokenStats: async (): Promise<{ total: number, available: number, assigned: number, damaged: number, lost: number }> => {
    const response = await apiClient.get('/api/v1/tokens/stats');
    return response.data;
  },

  updateTokenStatus: async (tokenId: number | string, status: string): Promise<any> => {
    const response = await apiClient.patch(`/api/v1/tokens/${tokenId}/status`, { status });
    return response.data;
  },

  deleteToken: async (tokenId: number | string): Promise<void> => {
    await apiClient.delete(`/api/v1/tokens/${tokenId}`);
  }
};

