import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getDashboardOverview } from '../dashboardApi';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { get: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('dashboardApi', () => {
  it('getDashboardOverview without status', async () => {
    const overview = { total_trips: 2, trips: [] };
    vi.mocked(apiClient.get).mockResolvedValue({ data: overview });
    const result = await getDashboardOverview();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/dashboard/overview', { params: {} });
    expect(result).toEqual(overview);
  });

  it('getDashboardOverview with ALL status', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: {} });
    await getDashboardOverview('ALL');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/dashboard/overview', { params: {} });
  });

  it('getDashboardOverview with specific status', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: {} });
    await getDashboardOverview('ACTIVE');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/dashboard/overview', { params: { status: 'ACTIVE' } });
  });
});
