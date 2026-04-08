import { describe, it, expect, vi, beforeEach } from 'vitest';
import { tokenApi } from '../tokenApi';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('tokenApi', () => {
  it('getTripAssignmentsStatus', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { total_students: 10, assigned_tokens: 5, remaining_students: 5 } });
    const result = await tokenApi.getTripAssignmentsStatus('t1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/trips/t1/assignments');
    expect(result.total_students).toBe(10);
  });

  it('getTripStudents', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { trip_id: 't1', students: [], total: 0, assigned: 0, unassigned: 0, assigned_digital: 0 } });
    const result = await tokenApi.getTripStudents('t1');
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/trips/t1/students');
    expect(result.trip_id).toBe('t1');
  });

  it('assignToken', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { id: 1 } });
    const result = await tokenApi.assignToken({ trip_id: 't1', student_id: 's1', token_uid: 'uid1', assignment_type: 'NFC_PHYSICAL' });
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/tokens/assign', { trip_id: 't1', student_id: 's1', token_uid: 'uid1', assignment_type: 'NFC_PHYSICAL' });
    expect(result).toEqual({ id: 1 });
  });

  it('reassignToken', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { id: 2 } });
    const result = await tokenApi.reassignToken({ trip_id: 't1', student_id: 's1', token_uid: 'uid2', assignment_type: 'QR_PHYSICAL', justification: 'Lost' });
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/tokens/reassign', expect.objectContaining({ justification: 'Lost' }));
    expect(result).toEqual({ id: 2 });
  });

  it('releaseTripTokens', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { trip_id: 't1', released_count: 5 } });
    const result = await tokenApi.releaseTripTokens('t1');
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/trips/t1/release-tokens');
    expect(result.released_count).toBe(5);
  });

  it('sendQrEmails', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { sent_count: 3, errors: [] } });
    const result = await tokenApi.sendQrEmails('t1');
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/trips/t1/send-qr-emails');
    expect(result.sent_count).toBe(3);
  });

  it('getExportUrl without password', () => {
    const url = tokenApi.getExportUrl('t1');
    expect(url).toContain('/api/v1/trips/t1/assignments/export');
    expect(url).not.toContain('password');
  });

  it('getExportUrl with password', () => {
    const url = tokenApi.getExportUrl('t1', 'secret');
    expect(url).toContain('password=secret');
  });

  it('getAllTokens with params', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: [{ id: 1 }] });
    const result = await tokenApi.getAllTokens({ status: 'AVAILABLE' });
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/tokens', { params: { status: 'AVAILABLE' } });
    expect(result).toEqual([{ id: 1 }]);
  });

  it('getTokenStats', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { total: 100, available: 50 } });
    const result = await tokenApi.getTokenStats();
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/tokens/stats');
    expect(result.total).toBe(100);
  });

  it('updateTokenStatus', async () => {
    vi.mocked(apiClient.patch).mockResolvedValue({ data: { id: 1, status: 'DAMAGED' } });
    const result = await tokenApi.updateTokenStatus(1, 'DAMAGED');
    expect(apiClient.patch).toHaveBeenCalledWith('/api/v1/tokens/1/status', { status: 'DAMAGED' });
    expect(result.status).toBe('DAMAGED');
  });

  it('deleteToken', async () => {
    vi.mocked(apiClient.delete).mockResolvedValue({});
    await tokenApi.deleteToken(1);
    expect(apiClient.delete).toHaveBeenCalledWith('/api/v1/tokens/1');
  });

  it('getTokenAssignmentInfo', async () => {
    vi.mocked(apiClient.get).mockResolvedValue({ data: { assignment_id: 1, student_name: 'Jean' } });
    const result = await tokenApi.getTokenAssignmentInfo(1);
    expect(apiClient.get).toHaveBeenCalledWith('/api/v1/tokens/1/assignment-info');
    expect(result.student_name).toBe('Jean');
  });

  it('releaseAssignment', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { assignment_id: 1, token_uid: 'uid1' } });
    const result = await tokenApi.releaseAssignment(1);
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/assignments/1/release');
    expect(result.token_uid).toBe('uid1');
  });
});
