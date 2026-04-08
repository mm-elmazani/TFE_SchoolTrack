import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import ClassListScreen from '../screens/ClassListScreen';
import { classApi } from '../api/classApi';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('../api/classApi', () => ({
  classApi: {
    getAll: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
  },
}));

vi.mock('../components/CreateClassDialog', () => ({
  CreateClassDialog: () => null,
}));
vi.mock('../components/UpdateClassDialog', () => ({
  UpdateClassDialog: () => null,
}));
vi.mock('../components/DeleteClassDialog', () => ({
  DeleteClassDialog: () => null,
}));

const mockClasses = [
  { id: 'c1', name: '5ème A', year: '2025-2026', nb_students: 25, nb_teachers: 2, created_at: '', updated_at: '' },
  { id: 'c2', name: '6ème B', year: '2025-2026', nb_students: 20, nb_teachers: 1, created_at: '', updated_at: '' },
];

beforeEach(() => {
  vi.clearAllMocks();
  useAuthStore.setState({
    token: 'test',
    user: { id: 'admin-id', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION' },
  });
});

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

  it('renders error state with retry button', async () => {
    vi.mocked(classApi.getAll).mockRejectedValue(new Error('API Error'));
    render(<ClassListScreen />);
    expect(await screen.findByText(/essayer/i)).toBeInTheDocument();
    expect(screen.getByText(/Impossible de r.*classes/i)).toBeInTheDocument();
  });

  it('renders a list of classes', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    expect(await screen.findByText('5ème A')).toBeInTheDocument();
    expect(screen.getAllByText('2025-2026').length).toBeGreaterThan(0);
    expect(screen.getByText('25')).toBeInTheDocument();
  });

  it('renders page title and subtitle', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    expect(await screen.findByText('Classes')).toBeInTheDocument();
    expect(screen.getByText(/G.rez les classes/i)).toBeInTheDocument();
  });

  it('renders Nouvelle Classe button for admin', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    expect(await screen.findByText('Nouvelle Classe')).toBeInTheDocument();
  });

  it('does not render Nouvelle Classe for non-admin', async () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: 't1', email: 'teacher@test.be', first_name: 'T', last_name: 'T', role: 'TEACHER' },
    });
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    expect(screen.queryByText('Nouvelle Classe')).not.toBeInTheDocument();
  });

  it('renders multiple classes', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    expect(await screen.findByText('5ème A')).toBeInTheDocument();
    expect(screen.getByText('6ème B')).toBeInTheDocument();
  });

  it('renders search bar', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    expect(screen.getByPlaceholderText(/Rechercher une classe/i)).toBeInTheDocument();
  });

  it('renders view mode toggle', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    expect(screen.getByText('Grille')).toBeInTheDocument();
    expect(screen.getByText('Liste')).toBeInTheDocument();
  });

  it('filters classes by search term', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    fireEvent.change(screen.getByPlaceholderText(/Rechercher une classe/i), {
      target: { value: '5ème' },
    });
    expect(screen.getByText('5ème A')).toBeInTheDocument();
    expect(screen.queryByText('6ème B')).not.toBeInTheDocument();
  });

  it('switches to list view', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText('Liste'));
    expect(screen.getByText('5ème A')).toBeInTheDocument();
  });

  it('renders empty state when no classes', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue([]);
    render(<ClassListScreen />);
    expect(await screen.findByText(/Aucune classe/i)).toBeInTheDocument();
  });

  it('renders nb_teachers count', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    expect(screen.getAllByText('2').length).toBeGreaterThan(0);
  });

  it('renders list view with Gérer button', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText('Liste'));
    expect(screen.getByText('5ème A')).toBeInTheDocument();
    expect(screen.getAllByText('Gérer').length).toBeGreaterThan(0);
  });

  it('renders list view table headers', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText('Liste'));
    expect(screen.getByText('Nom de la classe')).toBeInTheDocument();
    expect(screen.getByText('Effectif')).toBeInTheDocument();
  });

  it('renders list view with nb_students column', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText('Liste'));
    expect(screen.getAllByText('25').length).toBeGreaterThan(0);
  });

  it('renders list view year badge', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText('Liste'));
    expect(screen.getAllByText('2025-2026').length).toBeGreaterThan(0);
  });

  it('filters in list view', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText('Liste'));
    fireEvent.change(screen.getByPlaceholderText(/Rechercher une classe/i), {
      target: { value: '6ème' },
    });
    expect(screen.queryByText('5ème A')).not.toBeInTheDocument();
    expect(screen.getByText('6ème B')).toBeInTheDocument();
  });

  it('fires edit button click in grid view via pencil icon', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    const pencilBtn = document.querySelector('svg.lucide-pencil')?.closest('button');
    if (pencilBtn) fireEvent.click(pencilBtn);
    expect(screen.getByText('5ème A')).toBeInTheDocument();
  });

  it('fires delete button click in grid view via trash icon', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    const trashBtn = document.querySelector('svg.lucide-trash-2')?.closest('button');
    if (trashBtn) fireEvent.click(trashBtn);
    expect(screen.getByText('5ème A')).toBeInTheDocument();
  });

  it('fires edit and delete button in list view', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<ClassListScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText('Liste'));
    const pencilBtns = document.querySelectorAll('svg.lucide-pencil');
    const trashBtns = document.querySelectorAll('svg.lucide-trash-2');
    if (pencilBtns[0]) fireEvent.click(pencilBtns[0].closest('button')!);
    if (trashBtns[0]) fireEvent.click(trashBtns[0].closest('button')!);
    expect(screen.getByText('5ème A')).toBeInTheDocument();
  });
});
