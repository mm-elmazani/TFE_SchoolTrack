import { describe, it, expect, vi, beforeEach } from 'vitest';
import { classApi } from '../classApi';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('classApi', () => {
  it('getAll', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: [{ id: '1', name: '5A' }] });
    const result = await classApi.getAll();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/classes');
    expect(result).toEqual([{ id: '1', name: '5A' }]);
  });

  it('getById', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { id: '1' } });
    const result = await classApi.getById('1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/classes/1');
    expect(result).toEqual({ id: '1' });
  });

  it('create', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { id: '2', name: '6B' } });
    const result = await classApi.create({ name: '6B', year: '2025-2026' });
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/classes', { name: '6B', year: '2025-2026' });
    expect(result).toEqual({ id: '2', name: '6B' });
  });

  it('update', async () => {
    vi.mocked(apiClient.put).mockResolvedValue({ data: { id: '1', name: 'Updated' } });
    const result = await classApi.update('1', { name: 'Updated' });
    expect(apiClient.put).toHaveBeenCalledWith('/api/v1/classes/1', { name: 'Updated' });
    expect(result).toEqual({ id: '1', name: 'Updated' });
  });

  it('delete', async () => {
    vi.mocked(apiClient.delete).mockResolvedValue({});
    await classApi.delete('1');
    expect(apiClient.delete).toHaveBeenCalledWith('/api/v1/classes/1');
  });

  it('getStudents', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: ['s1', 's2'] });
    const result = await classApi.getStudents('1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/classes/1/students');
    expect(result).toEqual(['s1', 's2']);
  });

  it('assignStudents', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { id: '1' } });
    const result = await classApi.assignStudents('1', ['s1', 's2']);
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/classes/1/students', { student_ids: ['s1', 's2'] });
    expect(result).toEqual({ id: '1' });
  });

  it('removeStudent', async () => {
    vi.mocked(apiClient.delete).mockResolvedValue({});
    await classApi.removeStudent('c1', 's1');
    expect(apiClient.delete).toHaveBeenCalledWith('/api/v1/classes/c1/students/s1');
  });
});
