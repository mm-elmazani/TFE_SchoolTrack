import { describe, it, expect, vi, beforeEach } from 'vitest';
import { auditApi } from '../auditApi';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { get: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('auditApi', () => {
  it('getLogs with params', async () => {
    const page = { items: [], total: 0, page: 1, page_size: 20, total_pages: 0 };
    vi.mocked(apiClient.get).mockResolvedValue({ data: page });
    const result = await auditApi.getLogs({ page: 1, action: 'LOGIN' });
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/audit/logs', { params: { page: 1, action: 'LOGIN' } });
    expect(result).toEqual(page);
  });

  it('getLogs without params', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { items: [] } });
    await auditApi.getLogs();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/audit/logs', { params: undefined });
  });

  it('exportLogs returns blob', async () => {
    const blob = new Blob(['csv']);
    vi.mocked(apiClient.get).mockResolvedValue({ data: blob });
    const result = await auditApi.exportLogs({ action: 'LOGIN' });
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/audit/logs/export', {
      params: { action: 'LOGIN' },
      responseType: 'blob',
    });
    expect(result).toBe(blob);
  });
});
