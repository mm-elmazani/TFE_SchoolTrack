import { apiClient } from '@/api/axios';

export interface Enable2FAResponse {
  secret: string;
  provisioning_uri: string;
}

export interface MessageResponse {
  message: string;
}

export const authApi = {
  enable2FA: async (): Promise<Enable2FAResponse> => {
    const { data } = await apiClient.post<Enable2FAResponse>('/api/v1/auth/enable-2fa');
    return data;
  },

  verify2FA: async (totp_code: string): Promise<MessageResponse> => {
    const { data } = await apiClient.post<MessageResponse>('/api/v1/auth/verify-2fa', { totp_code });
    return data;
  },

  disable2FA: async (): Promise<MessageResponse> => {
    const { data } = await apiClient.post<MessageResponse>('/api/v1/auth/disable-2fa');
    return data;
  },

  enable2FAEmail: async (): Promise<MessageResponse> => {
    const { data } = await apiClient.post<MessageResponse>('/api/v1/auth/enable-2fa-email');
    return data;
  },

  verify2FAEmail: async (totp_code: string): Promise<MessageResponse> => {
    const { data } = await apiClient.post<MessageResponse>('/api/v1/auth/verify-2fa-email', { totp_code });
    return data;
  },

  resend2FACode: async (): Promise<MessageResponse> => {
    const { data } = await apiClient.post<MessageResponse>('/api/v1/auth/resend-2fa-code');
    return data;
  },

  changePassword: async (current_password: string, new_password: string): Promise<MessageResponse> => {
    const { data } = await apiClient.post<MessageResponse>('/api/v1/auth/change-password', {
      current_password,
      new_password,
    });
    return data;
  },
};
