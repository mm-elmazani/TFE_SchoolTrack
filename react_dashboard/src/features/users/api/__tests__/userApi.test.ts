import { describe, it, expect, vi, beforeEach } from 'vitest';
import { userApi } from '../userApi';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { get: vi.fn(), post: vi.fn(), delete: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('userApi', () => {
  it('getAll', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: [{ id: 'u1', email: 'test@test.be' }] });
    const result = await userApi.getAll();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/users');
    expect(result).toEqual([{ id: 'u1', email: 'test@test.be' }]);
  });

  it('create', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { id: 'u2' } });
    const result = await userApi.create({ email: 'new@test.be', password: 'Test123!', role: 'TEACHER' });
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/users', expect.objectContaining({ email: 'new@test.be' }));
    expect(result.id).toBe('u2');
  });

  it('delete', async () => {
    vi.mocked(apiClient.delete).mockResolvedValue({});
    await userApi.delete('u1');
    expect(apiClient.delete).toHaveBeenCalledWith('/api/v1/users/u1');
  });
});
