import { describe, it, expect, beforeEach } from 'vitest';
import { useAuthStore } from '../store/authStore';

describe('Auth Store', () => {
  beforeEach(() => {
    // Reset store before each test
    useAuthStore.setState({ token: null, user: null });
  });

  it('should initialize with null token and user', () => {
    const state = useAuthStore.getState();
    expect(state.token).toBeNull();
    expect(state.user).toBeNull();
  });

  it('should set auth token and user', () => {
    const testUser: any = { id: '1', email: 'test@test.com', role: 'DIRECTION' };
    useAuthStore.getState().setAuth('test-token', testUser);

    const state = useAuthStore.getState();
    expect(state.token).toBe('test-token');
    expect(state.user).toEqual(testUser);
  });

  it('should clear auth on logout', () => {
    const testUser: any = { id: '1', email: 'test@test.com', role: 'DIRECTION' };
    useAuthStore.getState().setAuth('test-token', testUser);
    useAuthStore.getState().logout();

    const state = useAuthStore.getState();
    expect(state.token).toBeNull();
    expect(state.user).toBeNull();
  });

  it('getIsAdmin should return true if user role is admin', () => {
    useAuthStore.getState().setAuth('test-token', { id: '1', email: 'test@test.com', role: 'DIRECTION' });
    expect(useAuthStore.getState().getIsAdmin()).toBe(true);
  });

  it('getIsAdmin should return false if user role is not admin', () => {
    useAuthStore.getState().setAuth('test-token', { id: '1', email: 'test@test.com', role: 'TEACHER' });
    expect(useAuthStore.getState().getIsAdmin()).toBe(false);
  });
});
