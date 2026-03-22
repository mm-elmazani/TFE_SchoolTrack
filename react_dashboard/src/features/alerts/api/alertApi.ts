import { apiClient } from '@/api/axios';

export interface AlertData {
  id: string;
  trip_id: string;
  checkpoint_id: string | null;
  student_id: string | null;
  student_name: string | null;
  trip_destination: string;
  checkpoint_name: string | null;
  alert_type: string;
  severity: 'CRITICAL' | 'HIGH' | 'MEDIUM' | 'LOW';
  message: string;
  status: 'ACTIVE' | 'IN_PROGRESS' | 'RESOLVED';
  created_at: string;
  resolved_at: string | null;
}

export interface AlertStats {
  total: number;
  active: number;
  in_progress: number;
  resolved: number;
  critical_count: number;
}

export async function getActiveAlerts(tripId?: string): Promise<AlertData[]> {
  const params: Record<string, string> = {};
  if (tripId) params.trip_id = tripId;
  const { data } = await apiClient.get('/api/v1/alerts/active', { params });
  return data;
}

export async function getAlerts(filters?: { trip_id?: string; status?: string }): Promise<AlertData[]> {
  const { data } = await apiClient.get('/api/v1/alerts', { params: filters });
  return data;
}

export async function getAlertStats(tripId?: string): Promise<AlertStats> {
  const params: Record<string, string> = {};
  if (tripId) params.trip_id = tripId;
  const { data } = await apiClient.get('/api/v1/alerts/stats', { params });
  return data;
}

export async function updateAlertStatus(alertId: string, status: string): Promise<AlertData> {
  const { data } = await apiClient.patch(`/api/v1/alerts/${alertId}`, { status });
  return data;
}
