import { apiClient } from '@/api/axios';

export interface AuditLog {
  id: string;
  action: string;
  user_id: string | null;
  user_email: string | null;
  resource_type: string | null;
  resource_id: string | null;
  ip_address: string | null;
  user_agent: string | null;
  details: any;
  performed_at: string;
}

export interface AuditLogPage {
  items: AuditLog[];
  total: number;
  page: number;
  page_size: number;
  total_pages: number;
}

export interface AuditLogFilters {
  page?: number;
  page_size?: number;
  action?: string;
  resource_type?: string;
  start_date?: string;
  end_date?: string;
}

export const auditApi = {
  getLogs: async (params?: AuditLogFilters): Promise<AuditLogPage> => {
    const response = await apiClient.get('/api/v1/audit/logs', { params });
    return response.data;
  },

  exportLogs: async (params?: Omit<AuditLogFilters, 'page' | 'page_size'>): Promise<Blob> => {
    const response = await apiClient.get('/api/v1/audit/logs/export', {
      params,
      responseType: 'blob' 
    });
    return response.data;
  }
};

