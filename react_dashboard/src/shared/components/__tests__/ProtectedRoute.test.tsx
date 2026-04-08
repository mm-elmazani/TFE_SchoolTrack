import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import ProtectedRoute from '../ProtectedRoute';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ schoolSlug: 'dev' }) };
});

describe('ProtectedRoute', () => {
  it('renders children when authenticated', () => {
    useAuthStore.setState({
      token: 'jwt-test',
      user: { id: '1', email: 'admin@test.be', role: 'DIRECTION' },
    });
    render(
      <ProtectedRoute>
        <div>Contenu protege</div>
      </ProtectedRoute>,
    );
    expect(screen.getByText('Contenu protege')).toBeInTheDocument();
  });

  it('does not render children when not authenticated', () => {
    useAuthStore.setState({ token: null, user: null });
    render(
      <ProtectedRoute>
        <div>Secret</div>
      </ProtectedRoute>,
    );
    expect(screen.queryByText('Secret')).not.toBeInTheDocument();
  });
});
