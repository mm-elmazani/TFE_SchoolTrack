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
  classes?: ClassSummary[];
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

  getCheckpointsSummary: async (tripId: string): Promise<CheckpointsSummary> => {
    const response = await apiClient.get(`/api/v1/trips/${tripId}/checkpoints-summary`);
    return response.data;
  },

  createCheckpoint: async (tripId: string, data: { name: string; description?: string }): Promise<CheckpointTimelineEntry> => {
    const response = await apiClient.post(`/api/v1/trips/${tripId}/checkpoints`, data);
    return response.data;
  },

  updateCheckpoint: async (checkpointId: string, data: { name: string; description?: string }): Promise<CheckpointTimelineEntry> => {
    const response = await apiClient.put(`/api/v1/checkpoints/${checkpointId}`, data);
    return response.data;
  },

  deleteCheckpoint: async (checkpointId: string): Promise<void> => {
    await apiClient.delete(`/api/v1/checkpoints/${checkpointId}`);
  },

  getExportUrl: (tripId: string): string => {
    const base = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    return `${base}/api/v1/trips/${tripId}/export`;
  },

  getBulkExportUrl: (tripIds: string[]): string => {
    const base = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    return `${base}/api/v1/trips/export-all?trip_ids=${tripIds.join(',')}`;
  },
};

export interface CheckpointTimelineEntry {
  id: string;
  name: string;
  description: string | null;
  sequence_order: number;
  status: string;
  created_at: string | null;
  started_at: string | null;
  closed_at: string | null;
  created_by_name: string | null;
  scan_count: number;
  student_count: number;
  duration_minutes: number | null;
}

export interface CheckpointsSummary {
  trip_id: string;
  trip_destination: string;
  total_checkpoints: number;
  active_checkpoints: number;
  closed_checkpoints: number;
  total_scans: number;
  avg_duration_minutes: number | null;
  timeline: CheckpointTimelineEntry[];
}
