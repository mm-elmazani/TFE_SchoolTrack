import { describe, it, expect, vi, beforeEach } from 'vitest';
import { tripApi } from '../tripApi';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('tripApi', () => {
  it('getAll', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: [{ id: 't1' }] });
    const result = await tripApi.getAll();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/trips');
    expect(result).toEqual([{ id: 't1' }]);
  });

  it('getById', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { id: 't1', destination: 'Bruges' } });
    const result = await tripApi.getById('t1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/trips/t1');
    expect(result.destination).toBe('Bruges');
  });

  it('create', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { id: 't2' } });
    const result = await tripApi.create({ destination: 'Gand', date: '2026-06-01', class_ids: ['c1'] });
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/trips', { destination: 'Gand', date: '2026-06-01', class_ids: ['c1'] });
    expect(result.id).toBe('t2');
  });

  it('update', async () => {
    vi.mocked(apiClient.put).mockResolvedValue({ data: { id: 't1', destination: 'Liege' } });
    const result = await tripApi.update('t1', { destination: 'Liege' });
    expect(apiClient.put).toHaveBeenCalledWith('/api/v1/trips/t1', { destination: 'Liege' });
    expect(result.destination).toBe('Liege');
  });

  it('archive', async () => {
    vi.mocked(apiClient.delete).mockResolvedValue({});
    await tripApi.archive('t1');
    expect(apiClient.delete).toHaveBeenCalledWith('/api/v1/trips/t1');
  });

  it('getCheckpointsSummary', async () => {
    const summary = { trip_id: 't1', total_checkpoints: 3, timeline: [] };
    vi.mocked(apiClient.get).mockResolvedValue({ data: summary });
    const result = await tripApi.getCheckpointsSummary('t1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/trips/t1/checkpoints-summary');
    expect(result.total_checkpoints).toBe(3);
  });

  it('getExportUrl', () => {
    const url = tripApi.getExportUrl('t1');
    expect(url).toContain('/api/v1/trips/t1/export');
  });

  it('getBulkExportUrl', () => {
    const url = tripApi.getBulkExportUrl(['t1', 't2']);
    expect(url).toContain('trip_ids=t1,t2');
  });
});
