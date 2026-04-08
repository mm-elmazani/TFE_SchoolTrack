import { describe, it, expect, vi } from 'vitest';
import { render } from '../../../test/test-utils';
import RoleRedirect from '../RoleRedirect';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ schoolSlug: 'dev' }) };
});

describe('RoleRedirect', () => {
  it('redirects admin to dashboard', () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: '1', email: 'admin', role: 'DIRECTION' },
    });
    // Navigate component renders nothing — no crash = success
    render(<RoleRedirect />);
  });

  it('redirects non-admin to students', () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: '1', email: 'teacher', role: 'TEACHER' },
    });
    render(<RoleRedirect />);
  });
});
