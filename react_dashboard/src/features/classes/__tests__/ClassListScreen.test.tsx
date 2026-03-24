import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import ClassListScreen from '../screens/ClassListScreen';
import { classApi } from '../api/classApi';
import { useAuthStore } from '@/features/auth/store/authStore';

// Mock API
vi.mock('../api/classApi', () => ({
  classApi: {
    getAll: vi.fn(),
  },
}));

describe('ClassListScreen', () => {
  it('renders loading state initially', () => {
    vi.mocked(classApi.getAll).mockReturnValue(new Promise(() => {}));
    render(<ClassListScreen />);
    expect(screen.getByText('Chargement des classes...')).toBeInTheDocument();
  });

  it('renders error state', async () => {
    vi.mocked(classApi.getAll).mockRejectedValue(new Error('API Error'));
    render(<ClassListScreen />);
    expect(await screen.findByText('Erreur de chargement')).toBeInTheDocument();
  });

  it('renders a list of classes', async () => {
    const mockClasses = [
      { id: '1', name: '5ème A', year: '2025-2026', nb_students: 25, nb_teachers: 2, created_at: '', updated_at: '' },
    ];
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    
    // Simulate admin login
    useAuthStore.setState({ token: 'test', user: { id: '1', email: 'admin', role: 'DIRECTION' } });

    render(<ClassListScreen />);
    
    expect(await screen.findByText('5ème A')).toBeInTheDocument();
    expect(screen.getByText('2025-2026')).toBeInTheDocument();
    expect(screen.getByText('25')).toBeInTheDocument();
  });
});
