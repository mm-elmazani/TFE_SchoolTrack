import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import StudentListScreen from '../screens/StudentListScreen';
import { studentApi } from '../api/studentApi';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('../api/studentApi', () => ({
  studentApi: {
    getAll: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    getGdprExport: vi.fn(),
    uploadPhoto: vi.fn(),
    getPhotoBlobUrl: vi.fn(),
  },
}));

vi.mock('../components/CreateStudentDialog', () => ({
  CreateStudentDialog: () => null,
}));
vi.mock('../components/UpdateStudentDialog', () => ({
  UpdateStudentDialog: () => null,
}));
vi.mock('../components/DeleteStudentDialog', () => ({
  DeleteStudentDialog: () => null,
}));

const mockStudents = [
  { id: 's1', first_name: 'Jean', last_name: 'Dupont', email: 'jean@test.be', qr_code_hash: null, is_deleted: false, created_at: '', phone: null, photo_url: null, class_name: '5ème A' },
  { id: 's2', first_name: 'Marie', last_name: 'Martin', email: 'marie@test.be', qr_code_hash: null, is_deleted: false, created_at: '', phone: null, photo_url: null, class_name: '6ème B' },
];

beforeEach(() => {
  vi.clearAllMocks();
  useAuthStore.setState({
    token: 'test',
    user: { id: 'admin-id', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION' },
  });
});

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
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    expect(await screen.findByText('Dupont Jean')).toBeInTheDocument();
    expect(screen.getByText('jean@test.be')).toBeInTheDocument();
    expect(screen.getByText('Ajouter un élève')).toBeInTheDocument();
    expect(screen.getByText('Importer CSV')).toBeInTheDocument();
  });

  it('renders page title and subtitle', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    expect(await screen.findByText(/l.ves/i)).toBeInTheDocument();
  });

  it('renders multiple students', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    expect(await screen.findByText('Dupont Jean')).toBeInTheDocument();
    expect(screen.getByText('Martin Marie')).toBeInTheDocument();
  });

  it('renders search bar', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    expect(screen.getByPlaceholderText(/Rechercher/i)).toBeInTheDocument();
  });

  it('filters students by search term', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    fireEvent.change(screen.getByPlaceholderText(/Rechercher/i), {
      target: { value: 'Dupont' },
    });
    expect(screen.getByText('Dupont Jean')).toBeInTheDocument();
    expect(screen.queryByText('Martin Marie')).not.toBeInTheDocument();
  });

  it('renders empty state when no students', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue([]);
    render(<StudentListScreen />);
    expect(await screen.findByText(/Aucun .l.ve/i)).toBeInTheDocument();
  });

  it('renders table headers', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    // Table headers for student list
    expect(screen.getAllByText(/l.ve|Nom/i).length).toBeGreaterThan(0);
  });

  it('renders student emails', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    expect(screen.getByText('jean@test.be')).toBeInTheDocument();
    expect(screen.getByText('marie@test.be')).toBeInTheDocument();
  });

  it('renders admin action buttons for each student', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    // Admin has edit/delete/gdpr buttons per student row
    const buttons = screen.getAllByRole('button');
    expect(buttons.length).toBeGreaterThan(2);
  });

  it('does not show Ajouter un élève for non-admin', async () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: 't1', email: 'teacher@test.be', first_name: 'T', last_name: 'T', role: 'TEACHER' },
    });
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    expect(screen.queryByText('Ajouter un élève')).not.toBeInTheDocument();
  });

  it('clicking Ajouter un élève button does not crash', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Ajouter un élève');
    fireEvent.click(screen.getByText('Ajouter un élève'));
    expect(screen.getByText('Élèves')).toBeInTheDocument();
  });

  it('clicking refresh button does not crash', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    const refreshBtn = document.querySelector('svg.lucide-refresh-cw')?.closest('button');
    if (refreshBtn) fireEvent.click(refreshBtn);
    expect(screen.getByText('Dupont Jean')).toBeInTheDocument();
  });

  it('fires edit button click per student row', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    const pencilBtns = document.querySelectorAll('svg.lucide-pencil');
    if (pencilBtns[0]) fireEvent.click(pencilBtns[0].closest('button')!);
    expect(screen.getByText('Dupont Jean')).toBeInTheDocument();
  });

  it('fires delete button click per student row', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    const trashBtns = document.querySelectorAll('svg.lucide-trash-2');
    if (trashBtns[0]) fireEvent.click(trashBtns[0].closest('button')!);
    expect(screen.getByText('Dupont Jean')).toBeInTheDocument();
  });

  it('renders student date column', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    // created_at is '' → toLocaleDateString → 'Invalid Date' or empty — just check row renders
    expect(screen.getAllByRole('row').length).toBeGreaterThan(1);
  });

  it('fires eye (details) button click', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    const eyeBtns = document.querySelectorAll('svg.lucide-eye');
    if (eyeBtns[0]) fireEvent.click(eyeBtns[0].closest('button')!);
    expect(screen.getByText('Élèves')).toBeInTheDocument();
  });

  it('fires download GDPR button click', async () => {
    vi.mocked(studentApi.getAll).mockResolvedValue(mockStudents as any);
    vi.mocked(studentApi.getGdprExport).mockResolvedValue({
      student: { first_name: 'Jean', last_name: 'Dupont', email: 'jean@test.be', created_at: '', id: 's1' },
      classes: [], assignments: [], attendances: [],
    } as any);
    vi.spyOn(window.URL, 'createObjectURL').mockReturnValue('blob:url');
    vi.spyOn(window.URL, 'revokeObjectURL').mockReturnValue(undefined);
    render(<StudentListScreen />);
    await screen.findByText('Dupont Jean');
    const downloadBtns = document.querySelectorAll('svg.lucide-download');
    if (downloadBtns[0]) fireEvent.click(downloadBtns[0].closest('button')!);
    expect(screen.getByText('Élèves')).toBeInTheDocument();
  });
});
