import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import UserListScreen from '../screens/UserListScreen';
import { userApi } from '../api/userApi';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('../api/userApi', () => ({
  userApi: {
    getAll: vi.fn(),
    delete: vi.fn(),
  },
}));

vi.mock('../components/CreateUserDialog', () => ({
  CreateUserDialog: () => null,
}));

const mockUsers = [
  { id: 'u1', email: 'prof@test.be', first_name: 'Jean', last_name: 'Dupont', role: 'TEACHER', is_2fa_enabled: false },
  { id: 'u2', email: 'dir@test.be', first_name: 'Marie', last_name: 'Martin', role: 'DIRECTION', is_2fa_enabled: true },
];

beforeEach(() => {
  vi.clearAllMocks();
  useAuthStore.setState({
    token: 'test',
    user: { id: 'admin-id', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION' },
  });
});

describe('UserListScreen', () => {
  it('renders loading state initially', () => {
    vi.mocked(userApi.getAll).mockReturnValue(new Promise(() => {}));
    render(<UserListScreen />);
    expect(screen.getByText('Chargement des utilisateurs...')).toBeInTheDocument();
  });

  it('renders a list of users', async () => {
    vi.mocked(userApi.getAll).mockResolvedValue(mockUsers as any);
    render(<UserListScreen />);
    expect(await screen.findByText('prof@test.be')).toBeInTheDocument();
    expect(screen.getByText('TEACHER')).toBeInTheDocument();
  });

  it('renders page title and subtitle', async () => {
    vi.mocked(userApi.getAll).mockResolvedValue(mockUsers as any);
    render(<UserListScreen />);
    expect(await screen.findByText('Utilisateurs')).toBeInTheDocument();
    expect(screen.getByText(/G.rez les professeurs/i)).toBeInTheDocument();
  });

  it('renders error state', async () => {
    vi.mocked(userApi.getAll).mockRejectedValue(new Error('API error'));
    render(<UserListScreen />);
    expect(await screen.findByText('Erreur de chargement')).toBeInTheDocument();
    expect(screen.getByText(/Impossible de r.*la liste des utilisateurs/i)).toBeInTheDocument();
  });

  it('renders empty state when no users', async () => {
    vi.mocked(userApi.getAll).mockResolvedValue([]);
    render(<UserListScreen />);
    expect(await screen.findByText(/Aucun utilisateur trouvé/i)).toBeInTheDocument();
  });

  it('renders 2FA activated badge', async () => {
    vi.mocked(userApi.getAll).mockResolvedValue(mockUsers as any);
    render(<UserListScreen />);
    await screen.findByText('prof@test.be');
    expect(screen.getByText('Activé')).toBeInTheDocument();
    expect(screen.getByText('Inactif')).toBeInTheDocument();
  });

  it('renders role badges', async () => {
    vi.mocked(userApi.getAll).mockResolvedValue(mockUsers as any);
    render(<UserListScreen />);
    await screen.findByText('prof@test.be');
    expect(screen.getByText('TEACHER')).toBeInTheDocument();
    expect(screen.getByText('DIRECTION')).toBeInTheDocument();
  });

  it('renders Nouvel Utilisateur button for admin', async () => {
    vi.mocked(userApi.getAll).mockResolvedValue(mockUsers as any);
    render(<UserListScreen />);
    expect(await screen.findByText('Nouvel Utilisateur')).toBeInTheDocument();
  });

  it('renders delete button for other users (not self)', async () => {
    vi.mocked(userApi.getAll).mockResolvedValue(mockUsers as any);
    render(<UserListScreen />);
    await screen.findByText('prof@test.be');
    // Delete buttons exist for users that are not the current user
    const deleteButtons = document.querySelectorAll('button');
    const trashButtons = Array.from(deleteButtons).filter(b =>
      b.className.includes('red') || b.querySelector('svg')
    );
    expect(trashButtons.length).toBeGreaterThan(0);
  });

  it('renders user emails in table', async () => {
    vi.mocked(userApi.getAll).mockResolvedValue(mockUsers as any);
    render(<UserListScreen />);
    expect(await screen.findByText('prof@test.be')).toBeInTheDocument();
    expect(screen.getByText('dir@test.be')).toBeInTheDocument();
  });

  it('renders Action restreinte for current user row', async () => {
    // The current user has id 'admin-id', so add that user to the list
    const usersWithSelf = [
      ...mockUsers,
      { id: 'admin-id', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION', is_2fa_enabled: true },
    ];
    vi.mocked(userApi.getAll).mockResolvedValue(usersWithSelf as any);
    render(<UserListScreen />);
    await screen.findByText('prof@test.be');
    expect(screen.getByText(/Action restreinte/i)).toBeInTheDocument();
  });

  it('renders error state retry button', async () => {
    vi.mocked(userApi.getAll).mockRejectedValue(new Error('API error'));
    render(<UserListScreen />);
    expect(await screen.findByText(/ssayer/i)).toBeInTheDocument();
  });

  it('clicking Nouvel Utilisateur does not crash', async () => {
    vi.mocked(userApi.getAll).mockResolvedValue(mockUsers as any);
    render(<UserListScreen />);
    const btn = await screen.findByText('Nouvel Utilisateur');
    fireEvent.click(btn);
    expect(screen.getByText('Utilisateurs')).toBeInTheDocument();
  });
});
