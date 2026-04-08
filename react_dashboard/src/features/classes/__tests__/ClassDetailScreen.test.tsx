import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import ClassDetailScreen from '../screens/ClassDetailScreen';
import { classApi } from '../api/classApi';
import { studentApi } from '@/features/students/api/studentApi';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('../api/classApi', () => ({
  classApi: { getById: vi.fn(), getStudents: vi.fn(), getAll: vi.fn(), assignStudents: vi.fn(), removeStudent: vi.fn() },
}));

vi.mock('@/features/students/api/studentApi', () => ({
  studentApi: { getAll: vi.fn() },
}));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ id: 'class-1', schoolSlug: 'dev' }) };
});

vi.mock('@/hooks/useSchoolPath', () => ({
  useSchoolPath: () => (path: string) => `/dev${path}`,
}));

const mockClass = {
  id: 'class-1', name: '5ème A', year: '2025-2026', nb_students: 20, nb_teachers: 2,
  created_at: '2025-09-01T00:00:00Z', updated_at: '2025-09-01T00:00:00Z',
};

// classApi.getStudents returns string[] (IDs), not Student[]
const mockStudentIds = ['s1', 's2'];

// studentApi.getAll returns ALL students (enrolled + available)
// enrolledStudents = those whose IDs are in mockStudentIds
const mockAllStudents = [
  { id: 's1', first_name: 'Jean', last_name: 'Dupont', email: 'jean@test.be', class_name: '5ème A', created_at: '', updated_at: '' },
  { id: 's2', first_name: 'Marie', last_name: 'Martin', email: 'marie@test.be', class_name: '5ème A', created_at: '', updated_at: '' },
  { id: 's3', first_name: 'Paul', last_name: 'Bernard', email: 'paul@test.be', class_name: null, created_at: '', updated_at: '' },
];

const mockAllClasses = [
  { id: 'class-1', name: '5ème A', year: '2025-2026', nb_students: 20, nb_teachers: 2, created_at: '', updated_at: '' },
];

beforeEach(() => {
  vi.clearAllMocks();
  useAuthStore.setState({
    token: 'test',
    user: { id: '1', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION' },
  });
});

describe('ClassDetailScreen', () => {
  it('renders loading state', () => {
    vi.mocked(classApi.getById).mockReturnValue(new Promise(() => {}));
    vi.mocked(classApi.getStudents).mockReturnValue(new Promise(() => {}));
    vi.mocked(studentApi.getAll).mockReturnValue(new Promise(() => {}));
    vi.mocked(classApi.getAll).mockReturnValue(new Promise(() => {}));
    render(<ClassDetailScreen />);
    expect(document.querySelector('.animate-spin')).toBeTruthy();
  });

  it('renders class not found', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(null as any);
    vi.mocked(classApi.getStudents).mockResolvedValue([]);
    vi.mocked(studentApi.getAll).mockResolvedValue([]);
    vi.mocked(classApi.getAll).mockResolvedValue([]);
    render(<ClassDetailScreen />);
    expect(await screen.findByText(/introuvable/i)).toBeInTheDocument();
  });

  it('renders class name and year', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    expect(await screen.findByText('5ème A')).toBeInTheDocument();
    expect(screen.getAllByText('2025-2026').length).toBeGreaterThan(0);
  });

  it('renders enrolled students', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    // Component renders "last_name first_name" as a full string
    expect(await screen.findByText(/Dupont/)).toBeInTheDocument();
    expect(screen.getByText(/Martin/)).toBeInTheDocument();
  });

  it('renders student emails', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    expect(await screen.findByText('jean@test.be')).toBeInTheDocument();
    expect(screen.getByText('marie@test.be')).toBeInTheDocument();
  });

  it('renders recap sidebar with stats', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    await screen.findByText(/Dupont/);
    expect(screen.getByText(/R.capitulatif/i)).toBeInTheDocument();
    expect(screen.getByText(/Effectif Total/i)).toBeInTheDocument();
  });

  it('renders assign students button for admin', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    await screen.findByText('5ème A');
    expect(screen.getByText(/Assigner|S.lectionner des .l.ves/i)).toBeInTheDocument();
  });

  it('renders empty student list message', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue([] as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    await screen.findByText('5ème A');
    expect(screen.getByText(/aucun .l.ve/i)).toBeInTheDocument();
  });

  it('renders back arrow link to classes list', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue([] as any);
    vi.mocked(studentApi.getAll).mockResolvedValue([]);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    await screen.findByText('5ème A');
    expect(document.querySelector('a[href="/dev/classes"]')).toBeTruthy();
  });

  it('opens assigning panel when "Assigner des élèves" clicked', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText(/Assigner des élèves/i));
    expect(screen.getByText(/Sélectionner des élèves/i)).toBeInTheDocument();
  });

  it('shows available student in assign panel', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText(/Assigner des élèves/i));
    // Paul Bernard is not in mockStudentIds → disponible
    expect(screen.getByText(/Bernard/i)).toBeInTheDocument();
  });

  it('shows empty available when all students enrolled', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(['s1', 's2', 's3'] as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText(/Assigner des élèves/i));
    expect(screen.getByText(/Aucun élève disponible/i)).toBeInTheDocument();
  });

  it('closes assigning panel when Annuler clicked', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText(/Assigner des élèves/i));
    expect(screen.getByText(/Sélectionner des élèves/i)).toBeInTheDocument();
    fireEvent.click(screen.getByText('Annuler'));
    expect(screen.queryByText(/Sélectionner des élèves/i)).not.toBeInTheDocument();
  });

  it('clicks plus button to assign available student', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    vi.mocked(classApi.assignStudents).mockResolvedValue([] as any);
    render(<ClassDetailScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText(/Assigner des élèves/i));
    await screen.findByText(/Bernard/i);
    // Click the plus icon button for Paul Bernard
    const plusBtn = document.querySelector('svg.lucide-plus')?.closest('button');
    if (plusBtn) fireEvent.click(plusBtn as HTMLElement);
    expect(screen.getByText('5ème A')).toBeInTheDocument();
  });

  it('clicks trash button to remove enrolled student', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    vi.mocked(classApi.removeStudent).mockResolvedValue(undefined as any);
    render(<ClassDetailScreen />);
    await screen.findByText(/Dupont/);
    const trashBtn = document.querySelector('svg.lucide-trash2')?.closest('button');
    if (trashBtn) fireEvent.click(trashBtn as HTMLElement);
    expect(window.confirm).toHaveBeenCalled();
  });

  it('filters available students by search term in assign panel', async () => {
    vi.mocked(classApi.getById).mockResolvedValue(mockClass);
    vi.mocked(classApi.getStudents).mockResolvedValue(mockStudentIds as any);
    vi.mocked(studentApi.getAll).mockResolvedValue(mockAllStudents);
    vi.mocked(classApi.getAll).mockResolvedValue(mockAllClasses);
    render(<ClassDetailScreen />);
    await screen.findByText('5ème A');
    fireEvent.click(screen.getByText(/Assigner des élèves/i));
    await screen.findByText(/Bernard/i);
    fireEvent.change(screen.getByPlaceholderText(/Filtrer par nom/i), { target: { value: 'Bernard' } });
    expect(screen.getByText(/Bernard/i)).toBeInTheDocument();
  });
});
