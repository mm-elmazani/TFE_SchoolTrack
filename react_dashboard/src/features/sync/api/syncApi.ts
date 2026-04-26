import { apiClient } from '@/api/axios';

export interface SyncStats {
  total_syncs: number;
  total_records_synced: number;
  total_conflicts: number;
  success_count: number;
  partial_count: number;
  failed_count: number;
  last_sync_at: string | null;
}

export interface SyncLogItem {
  id: string;
  user_id: string | null;
  user_email: string | null;
  trip_id: string | null;
  trip_name: string | null;
  device_id: string | null;
  records_synced: number;
  conflicts_detected: number;
  status: 'SUCCESS' | 'PARTIAL' | 'FAILED';
  error_details: string | null;
  synced_at: string;
}

export interface SyncLogPage {
  items: SyncLogItem[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

export const syncApi = {
  getStats: async (): Promise<SyncStats> => {
    const response = await apiClient.get('/api/sync/stats');
    return response.data;
  },

  getLogs: async (params: {
    page?: number;
    page_size?: number;
    status?: string;
    trip_id?: string;
  }): Promise<SyncLogPage> => {
    const response = await apiClient.get('/api/sync/logs', { params });
    return response.data;
  },
};
