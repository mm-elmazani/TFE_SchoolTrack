import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import UserListScreen from '../screens/UserListScreen';
import { userApi } from '../api/userApi';
import { useAuthStore } from '@/features/auth/store/authStore';

// Mock API
vi.mock('../api/userApi', () => ({
  userApi: {
    getAll: vi.fn(),
  },
}));

describe('UserListScreen', () => {
  it('renders loading state initially', () => {
    vi.mocked(userApi.getAll).mockReturnValue(new Promise(() => {}));
    render(<UserListScreen />);
    expect(screen.getByText('Chargement des utilisateurs...')).toBeInTheDocument();
  });

  it('renders a list of users', async () => {
    const mockUsers = [
      { id: '1', email: 'prof@test.com', first_name: 'Prof', last_name: 'Test', role: 'TEACHER', is_2fa_enabled: false },
    ];
    vi.mocked(userApi.getAll).mockResolvedValue(mockUsers);
    useAuthStore.setState({ token: 'test', user: { id: '99', email: 'admin', role: 'DIRECTION' } });

    render(<UserListScreen />);
    
    expect(await screen.findByText('prof@test.com')).toBeInTheDocument();
    expect(screen.getByText('TEACHER')).toBeInTheDocument();
    expect(screen.getByText('Inactif')).toBeInTheDocument();
  });
});
