import { describe, it, expect, beforeEach } from 'vitest';
import { useAuthStore } from '../store/authStore';

describe('Auth Store', () => {
  beforeEach(() => {
    useAuthStore.setState({ token: null, refreshToken: null, user: null });
  });

  it('should initialize with null token, refreshToken and user', () => {
    const state = useAuthStore.getState();
    expect(state.token).toBeNull();
    expect(state.refreshToken).toBeNull();
    expect(state.user).toBeNull();
  });

  it('should set auth token, refreshToken and user', () => {
    const testUser: any = { id: '1', email: 'test@test.com', role: 'DIRECTION' };
    useAuthStore.getState().setAuth('test-token', 'test-refresh', testUser);

    const state = useAuthStore.getState();
    expect(state.token).toBe('test-token');
    expect(state.refreshToken).toBe('test-refresh');
    expect(state.user).toEqual(testUser);
  });

  it('should clear auth on logout', () => {
    const testUser: any = { id: '1', email: 'test@test.com', role: 'DIRECTION' };
    useAuthStore.getState().setAuth('test-token', 'test-refresh', testUser);
    useAuthStore.getState().logout();

    const state = useAuthStore.getState();
    expect(state.token).toBeNull();
    expect(state.refreshToken).toBeNull();
    expect(state.user).toBeNull();
  });

  it('should update tokens via setTokens', () => {
    const testUser: any = { id: '1', email: 'test@test.com', role: 'DIRECTION' };
    useAuthStore.getState().setAuth('old-token', 'old-refresh', testUser);
    useAuthStore.getState().setTokens('new-token', 'new-refresh');

    const state = useAuthStore.getState();
    expect(state.token).toBe('new-token');
    expect(state.refreshToken).toBe('new-refresh');
    expect(state.user).toEqual(testUser);
  });

  it('getIsAdmin should return true for DIRECTION', () => {
    useAuthStore.getState().setAuth('t', 'r', { id: '1', email: 'test@test.com', role: 'DIRECTION' });
    expect(useAuthStore.getState().getIsAdmin()).toBe(true);
  });

  it('getIsAdmin should return true for ADMIN_TECH', () => {
    useAuthStore.getState().setAuth('t', 'r', { id: '1', email: 'test@test.com', role: 'ADMIN_TECH' });
    expect(useAuthStore.getState().getIsAdmin()).toBe(true);
  });

  it('getIsAdmin should return false for TEACHER', () => {
    useAuthStore.getState().setAuth('t', 'r', { id: '1', email: 'test@test.com', role: 'TEACHER' });
    expect(useAuthStore.getState().getIsAdmin()).toBe(false);
  });

  it('getIsObserver should return true for OBSERVER', () => {
    useAuthStore.getState().setAuth('t', 'r', { id: '1', email: 'test@test.com', role: 'OBSERVER' });
    expect(useAuthStore.getState().getIsObserver()).toBe(true);
  });

  it('getCanManageStudents should include TEACHER', () => {
    useAuthStore.getState().setAuth('t', 'r', { id: '1', email: 'test@test.com', role: 'TEACHER' });
    expect(useAuthStore.getState().getCanManageStudents()).toBe(true);
  });
});
