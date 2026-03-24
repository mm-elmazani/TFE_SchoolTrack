import { apiClient } from '@/api/axios';

export interface CheckpointSummary {
  id: string;
  name: string;
  sequence_order: number;
  status: string;
  total_expected: number;
  total_present: number;
  attendance_rate: number;
  closed_at: string | null;
}

export interface DashboardTripSummary {
  id: string;
  destination: string;
  date: string;
  status: string;
  total_students: number;
  total_present: number;
  attendance_rate: number;
  total_checkpoints: number;
  closed_checkpoints: number;
  last_checkpoint: CheckpointSummary | null;
  checkpoints: CheckpointSummary[];
}

export interface ScanMethodStats {
  nfc: number;
  qr_physical: number;
  qr_digital: number;
  manual: number;
  total: number;
}

export interface DashboardOverview {
  total_trips: number;
  active_trips: number;
  planned_trips: number;
  completed_trips: number;
  total_students: number;
  total_attendances: number;
  global_attendance_rate: number;
  scan_method_stats: ScanMethodStats;
  trips: DashboardTripSummary[];
  generated_at: string;
}

export async function getDashboardOverview(status?: string): Promise<DashboardOverview> {
  const params = status && status !== 'ALL' ? { status } : {};
  const { data } = await apiClient.get('/api/v1/dashboard/overview', { params });
  return data;
}
