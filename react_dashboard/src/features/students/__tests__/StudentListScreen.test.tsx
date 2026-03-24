import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import StudentListScreen from '../screens/StudentListScreen';
import { studentApi } from '../api/studentApi';
import { useAuthStore } from '@/features/auth/store/authStore';

// Mock API
vi.mock('../api/studentApi', () => ({
  studentApi: {
    getAll: vi.fn(),
  },
}));

describe('StudentListScreen', () => {
  it('renders loading state initially', () => {
    vi.mocked(studentApi.getAll).mockReturnValue(new Promise(() => {}));
    render(<StudentListScreen />);
    expect(screen.getByText('Chargement des élèves...')).toBeInTheDocument();
  });

  it('renders error state', async () => {
    vi.mocked(studentApi.getAll).mockRejectedValue(new Error('API Error'));
    render(<StudentListScreen />);
    expect(await screen.findByText('Erreur de chargement')).toBeInTheDocument();
  });

  it('renders a list of students', async () => {
    const mockStudents = [
      { id: '1', first_name: 'John', last_name: 'Doe', email: 'john@test.com', qr_code_hash: null, is_deleted: false, created_at: '' },
    ];
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents);
    
    // Simulate admin login
    useAuthStore.setState({ token: 'test', user: { id: '1', email: 'admin', role: 'DIRECTION' } });

    render(<StudentListScreen />);
    
    expect(await screen.findByText('Doe John')).toBeInTheDocument();
    expect(screen.getByText('john@test.com')).toBeInTheDocument();
    
    // Admin buttons should be visible
    expect(screen.getByText('Ajouter un élève')).toBeInTheDocument();
    expect(screen.getByText('Importer CSV')).toBeInTheDocument();
  });
});
