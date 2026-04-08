import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import StudentDetailScreen from '../screens/StudentDetailScreen';
import { studentApi } from '../api/studentApi';

vi.mock('../api/studentApi', () => ({
  studentApi: { getGdprExport: vi.fn() },
}));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ id: 'student-1', schoolSlug: 'dev' }) };
});

vi.mock('@/hooks/useSchoolPath', () => ({
  useSchoolPath: () => (path: string) => `/dev${path}`,
}));

const mockGdprData = {
  student: {
    id: 's1', first_name: 'Jean', last_name: 'Dupont',
    email: 'jean@test.be', created_at: '2026-01-01T00:00:00Z',
    photo_consent: true, parent_consent: true, is_deleted: false,
  },
  classes: [
    { class_id: 'c1', class_name: '5ème A', enrolled_at: '2026-01-01T00:00:00Z' },
  ],
  assignments: [
    { id: 'a1', token_uid: 'NFC-001', assignment_type: 'NFC_PHYSICAL', assigned_at: '2026-01-10T00:00:00Z', released_at: null },
  ],
  attendances: [
    { id: 'att1', scanned_at: '2026-05-10T10:00:00Z', scan_method: 'NFC', is_manual: false, justification: null, comment: null },
  ],
};

describe('StudentDetailScreen', () => {
  it('renders loading state', () => {
    vi.mocked(studentApi.getGdprExport).mockReturnValue(new Promise(() => {}));
    render(<StudentDetailScreen />);
    expect(document.querySelector('.animate-spin')).toBeTruthy();
  });

  it('renders error state', async () => {
    vi.mocked(studentApi.getGdprExport).mockRejectedValue(new Error('Not found'));
    render(<StudentDetailScreen />);
    expect(await screen.findByText(/introuvable/i)).toBeInTheDocument();
  });

  it('renders back to list link on error', async () => {
    vi.mocked(studentApi.getGdprExport).mockRejectedValue(new Error('Not found'));
    render(<StudentDetailScreen />);
    await screen.findByText(/introuvable/i);
    expect(screen.getByText(/Retour/i)).toBeInTheDocument();
  });

  it('renders student full name', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue(mockGdprData);
    render(<StudentDetailScreen />);
    expect(await screen.findByText(/Jean/)).toBeInTheDocument();
    expect(screen.getByText(/Dupont/)).toBeInTheDocument();
  });

  it('renders student email', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue(mockGdprData);
    render(<StudentDetailScreen />);
    expect(await screen.findByText('jean@test.be')).toBeInTheDocument();
  });

  it('renders Exporter Profil button', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue(mockGdprData);
    render(<StudentDetailScreen />);
    expect(await screen.findByText(/Exporter Profil/i)).toBeInTheDocument();
  });

  it('renders classes section', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue(mockGdprData);
    render(<StudentDetailScreen />);
    await screen.findByText(/Jean/);
    expect(screen.getAllByText(/Classes/i).length).toBeGreaterThan(0);
    expect(screen.getByText('5ème A')).toBeInTheDocument();
  });

  it('renders assignments section', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue(mockGdprData);
    render(<StudentDetailScreen />);
    await screen.findByText(/Jean/);
    expect(screen.getByText('NFC-001')).toBeInTheDocument();
  });

  it('renders attendances section header', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue(mockGdprData);
    render(<StudentDetailScreen />);
    await screen.findByText(/Jean/);
    expect(screen.getByText(/Historique des Pr.sences/i)).toBeInTheDocument();
  });

  it('renders consent badge', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue(mockGdprData);
    render(<StudentDetailScreen />);
    await screen.findByText(/Jean/);
    expect(screen.getByText(/Accord/i)).toBeInTheDocument();
  });

  it('renders empty class message when no classes', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue({ ...mockGdprData, classes: [] });
    render(<StudentDetailScreen />);
    await screen.findByText(/Jean/);
    expect(screen.getByText(/Aucune classe enregistr.e/i)).toBeInTheDocument();
  });

  it('renders empty assignment message when no assignments', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue({ ...mockGdprData, assignments: [] });
    render(<StudentDetailScreen />);
    await screen.findByText(/Jean/);
    expect(screen.getByText(/Aucun bracelet historis/i)).toBeInTheDocument();
  });

  it('renders empty attendance message when no attendances', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue({ ...mockGdprData, attendances: [] });
    render(<StudentDetailScreen />);
    await screen.findByText(/Jean/);
    expect(screen.getByText(/Aucun scan enregistr/i)).toBeInTheDocument();
  });

  it('renders Actif badge for active assignment', async () => {
    vi.mocked(studentApi.getGdprExport).mockResolvedValue(mockGdprData);
    render(<StudentDetailScreen />);
    await screen.findByText('NFC-001');
    expect(screen.getByText('Actif')).toBeInTheDocument();
  });

  it('renders Libéré badge for released assignment', async () => {
    const dataWithReleased = {
      ...mockGdprData,
      assignments: [
        { id: 'a2', token_uid: 'NFC-002', assignment_type: 'NFC_PHYSICAL', assigned_at: '2026-01-01T00:00:00Z', released_at: '2026-02-01T00:00:00Z' },
      ],
    };
    vi.mocked(studentApi.getGdprExport).mockResolvedValue(dataWithReleased);
    render(<StudentDetailScreen />);
    await screen.findByText('NFC-002');
    expect(screen.getByText(/Lib.r/i)).toBeInTheDocument();
  });
});
