import { describe, it, expect, vi, beforeEach } from 'vitest';
import { authApi } from '../authApi';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { post: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('authApi', () => {
  it('enable2FA', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { secret: 's', provisioning_uri: 'u' } });
    const result = await authApi.enable2FA();
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/auth/enable-2fa');
    expect(result).toEqual({ secret: 's', provisioning_uri: 'u' });
  });

  it('verify2FA', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { message: 'ok' } });
    const result = await authApi.verify2FA('123456');
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/auth/verify-2fa', { totp_code: '123456' });
    expect(result).toEqual({ message: 'ok' });
  });

  it('disable2FA', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { message: 'disabled' } });
    const result = await authApi.disable2FA();
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/auth/disable-2fa');
    expect(result).toEqual({ message: 'disabled' });
  });

  it('enable2FAEmail', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { message: 'sent' } });
    const result = await authApi.enable2FAEmail();
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/auth/enable-2fa-email');
    expect(result).toEqual({ message: 'sent' });
  });

  it('verify2FAEmail', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { message: 'verified' } });
    const result = await authApi.verify2FAEmail('654321');
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/auth/verify-2fa-email', { totp_code: '654321' });
    expect(result).toEqual({ message: 'verified' });
  });

  it('resend2FACode', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { message: 'resent' } });
    const result = await authApi.resend2FACode();
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/auth/resend-2fa-code');
    expect(result).toEqual({ message: 'resent' });
  });

  it('changePassword', async () => {
    vi.mocked(apiClient.post).mockResolvedValue({ data: { message: 'changed' } });
    const result = await authApi.changePassword('old', 'new');
    expect(apiClient.post).toHaveBeenCalledWith('/api/v1/auth/change-password', {
      current_password: 'old',
      new_password: 'new',
    });
    expect(result).toEqual({ message: 'changed' });
  });
});
