import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getAlerts, getAlertStats, getActiveAlerts, updateAlertStatus } from '../alertApi';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { get: vi.fn(), post: vi.fn(), patch: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('alertApi', () => {
  it('getAlerts with filters', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: [{ id: '1' }] });
    const result = await getAlerts({ status: 'ACTIVE' });
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/alerts', { params: { status: 'ACTIVE' } });
    expect(result).toEqual([{ id: '1' }]);
  });

  it('getAlerts without filters', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: [] });
    const result = await getAlerts();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/alerts', { params: undefined });
    expect(result).toEqual([]);
  });

  it('getAlertStats without tripId', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { active: 1, total: 5 } });
    const result = await getAlertStats();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/alerts/stats', { params: {} });
    expect(result).toEqual({ active: 1, total: 5 });
  });

  it('getAlertStats with tripId', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { active: 0 } });
    await getAlertStats('trip-1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/alerts/stats', { params: { trip_id: 'trip-1' } });
  });

  it('getActiveAlerts without tripId', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: [] });
    const result = await getActiveAlerts();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/alerts/active', { params: {} });
    expect(result).toEqual([]);
  });

  it('getActiveAlerts with tripId', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: [{ id: 'a1' }] });
    await getActiveAlerts('trip-1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/alerts/active', { params: { trip_id: 'trip-1' } });
  });

  it('updateAlertStatus', async () => {
    vi.mocked(apiClient.patch).mockResolvedValue({ data: { id: 'a1', status: 'RESOLVED' } });
    const result = await updateAlertStatus('a1', 'RESOLVED');
    expect(apiClient.patch).toHaveBeenCalledWith('/api/v1/alerts/a1', { status: 'RESOLVED' });
    expect(result).toEqual({ id: 'a1', status: 'RESOLVED' });
  });
});
