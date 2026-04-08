import { describe, it, expect, vi, beforeEach } from 'vitest';
import { studentApi } from '../studentApi';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('studentApi', () => {
  it('getAll', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: [{ id: 's1' }] });
    const result = await studentApi.getAll();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/students');
    expect(result).toEqual([{ id: 's1' }]);
  });

  it('create', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { id: 's2' } });
    const result = await studentApi.create({ first_name: 'Jean', last_name: 'Dupont' });
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/students', { first_name: 'Jean', last_name: 'Dupont' });
    expect(result).toEqual({ id: 's2' });
  });

  it('uploadPhoto', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { id: 's1', photo_url: '/photo.jpg' } });
    const file = new File(['img'], 'photo.jpg', { type: 'image/jpeg' });
    const result = await studentApi.uploadPhoto('s1', file);
    expect(apiClient.post).toHaveBeenCalledWith(
      '/api/v1/students/s1/photo',
      expect.any(FormData),
      { headers: { 'Content-Type': 'multipart/form-data' } },
    );
    expect(result).toEqual({ id: 's1', photo_url: '/photo.jpg' });
  });

  it('getPhotoBlobUrl', async () => {
    const blob = new Blob(['img']);
    vi.mocked(apiClient.get).mockResolvedValue({ data: blob });
    global.URL.createObjectURL = vi.fn().mockReturnValue('blob:url');
    const result = await studentApi.getPhotoBlobUrl('s1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/students/s1/photo', { responseType: 'blob' });
    expect(result).toBe('blob:url');
  });

  it('uploadCsv', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { inserted: 5, rejected: 1 } });
    const file = new File(['csv'], 'students.csv', { type: 'text/csv' });
    const result = await studentApi.uploadCsv(file);
    expect(apiClient.post).toHaveBeenCalledWith(
      '/api/v1/students/upload',
      expect.any(FormData),
      { headers: { 'Content-Type': 'multipart/form-data' } },
    );
    expect(result).toEqual({ inserted: 5, rejected: 1 });
  });

  it('update', async () => {
    vi.mocked(apiClient.put).mockResolvedValue({ data: { id: 's1' } });
    const result = await studentApi.update('s1', { first_name: 'Pierre' });
    expect(apiClient.put).toHaveBeenCalledWith('/api/v1/students/s1', { first_name: 'Pierre' });
    expect(result).toEqual({ id: 's1' });
  });

  it('delete', async () => {
    vi.mocked(apiClient.delete).mockResolvedValue({});
    await studentApi.delete('s1');
    expect(apiClient.delete).toHaveBeenCalledWith('/api/v1/students/s1');
  });

  it('getGdprExport', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { student: {}, classes: [] } });
    const result = await studentApi.getGdprExport('s1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/students/s1/data-export');
    expect(result).toEqual({ student: {}, classes: [] });
  });
});
