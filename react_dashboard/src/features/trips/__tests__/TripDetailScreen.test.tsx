import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import userEvent from '@testing-library/user-event';
import TripDetailScreen from '../screens/TripDetailScreen';
import { tripApi } from '../api/tripApi';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('../api/tripApi', () => ({
  tripApi: {
    getById: vi.fn(),
    getCheckpointsSummary: vi.fn(),
    createCheckpoint: vi.fn(),
    updateCheckpoint: vi.fn(),
    deleteCheckpoint: vi.fn(),
  },
}));

vi.mock('../components/UpdateTripDialog', () => ({
  UpdateTripDialog: () => null,
}));

vi.mock('../components/CreateCheckpointDialog', () => ({
  CreateCheckpointDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="create-checkpoint-dialog" /> : null,
}));

vi.mock('../components/EditCheckpointDialog', () => ({
  EditCheckpointDialog: ({ open }: { open: boolean }) =>
    open ? <div data-testid="edit-checkpoint-dialog" /> : null,
}));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ id: 'trip-1', schoolSlug: 'dev' }) };
});

vi.mock('@/hooks/useSchoolPath', () => ({
  useSchoolPath: () => (path: string) => `/dev${path}`,
}));

const mockTrip = {
  id: 'trip-1', destination: 'Bruges', date: '2026-06-15', status: 'ACTIVE',
  classes: [], total_students: 25, description: 'Excursion culturelle',
  created_at: '2026-01-01', updated_at: '2026-01-01',
};

const mockCheckpointsSummary = {
  total_checkpoints: 2,
  total_scans: 45,
  timeline: [
    { id: 'cp1', name: 'Départ', status: 'CLOSED', scan_count: 24, student_count: 25, description: null, sequence_order: 1, created_at: '2026-06-15T08:00:00Z', started_at: null, closed_at: null, created_by_name: null, duration_minutes: null },
    { id: 'cp2', name: 'Arrivée', status: 'ACTIVE', scan_count: 20, student_count: 25, description: null, sequence_order: 2, created_at: '2026-06-15T10:00:00Z', started_at: null, closed_at: null, created_by_name: null, duration_minutes: null },
  ],
};

const mockCheckpointsSummaryWithDraft = {
  total_checkpoints: 1,
  total_scans: 0,
  timeline: [
    { id: 'cp-draft', name: 'Accueil', status: 'DRAFT', scan_count: 0, student_count: 0, description: null, sequence_order: 1, created_at: null, started_at: null, closed_at: null, created_by_name: null, duration_minutes: null },
  ],
};

beforeEach(() => {
  vi.clearAllMocks();
  useAuthStore.setState({
    token: 'test',
    user: { id: '1', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION' },
  });
});

describe('TripDetailScreen', () => {
  it('renders loading state', () => {
    vi.mocked(tripApi.getById).mockReturnValue(new Promise(() => {}));
    vi.mocked(tripApi.getCheckpointsSummary).mockReturnValue(new Promise(() => {}));
    render(<TripDetailScreen />);
    expect(document.querySelector('.animate-spin')).toBeTruthy();
  });

  it('renders error state', async () => {
    vi.mocked(tripApi.getById).mockRejectedValue(new Error('Not found'));
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([]);
    render(<TripDetailScreen />);
    expect(await screen.findByText('Voyage introuvable')).toBeInTheDocument();
  });

  it('renders back link on error', async () => {
    vi.mocked(tripApi.getById).mockRejectedValue(new Error('Not found'));
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([]);
    render(<TripDetailScreen />);
    await screen.findByText('Voyage introuvable');
    expect(screen.getByText(/Retour à la liste/i)).toBeInTheDocument();
  });

  it('renders trip destination', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummary as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText('Bruges')).toBeInTheDocument();
  });

  it('renders ACTIVE status badge', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummary as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/En cours/i)).toBeInTheDocument();
  });

  it('renders PLANNED status badge', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'PLANNED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/À venir/i)).toBeInTheDocument();
  });

  it('renders COMPLETED status badge', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'COMPLETED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/Terminé/i)).toBeInTheDocument();
  });

  it('renders ARCHIVED status badge', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'ARCHIVED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/Archivé/i)).toBeInTheDocument();
  });

  it('renders student count', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/25 élèves inscrits/i)).toBeInTheDocument();
  });

  it('renders empty classes message', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/Aucune classe n'est assignée/i)).toBeInTheDocument();
  });

  it('renders classes when trip has classes', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({
      ...mockTrip,
      classes: [
        { id: 'c1', name: '5ème A', year: '2025-2026', student_count: 20 },
      ],
    } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText('5ème A')).toBeInTheDocument();
    expect(screen.getByText('2025-2026')).toBeInTheDocument();
    expect(screen.getByText(/20 élèves/i)).toBeInTheDocument();
  });

  it('renders checkpoints tab content after click', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    const user = userEvent.setup();
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    expect(await screen.findByText(/Aucun checkpoint enregistré/i)).toBeInTheDocument();
  });

  it('renders checkpoints timeline when available', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummary as any);
    const user = userEvent.setup();
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    expect(await screen.findByText('Départ')).toBeInTheDocument();
    expect(await screen.findByText('Arrivée')).toBeInTheDocument();
  });

  it('renders Modifier le voyage button for admin on non-archived trip', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText(/Modifier le voyage/i)).toBeInTheDocument();
  });

  it('does not render Modifier button for archived trip', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'ARCHIVED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    await screen.findByText(/Archivé/i);
    expect(screen.queryByText(/Modifier le voyage/i)).not.toBeInTheDocument();
  });

  it('renders Classes inscrites tab header', async () => {
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    expect(await screen.findByText('Classes inscrites')).toBeInTheDocument();
  });

  // ----------------------------------------------------------------
  // Gestion des checkpoints depuis le dashboard
  // ----------------------------------------------------------------

  it('affiche le bouton Ajouter pour un voyage ACTIVE', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummary as any);
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    expect(await screen.findByRole('button', { name: /Ajouter/i })).toBeInTheDocument();
  });

  it('n\'affiche pas le bouton Ajouter pour un voyage COMPLETED', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'COMPLETED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    await screen.findByText(/Aucun checkpoint/i);
    expect(screen.queryByRole('button', { name: /Ajouter/i })).not.toBeInTheDocument();
  });

  it('n\'affiche pas le bouton Ajouter pour un voyage ARCHIVED', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.getById).mockResolvedValue({ ...mockTrip, status: 'ARCHIVED' } as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    await screen.findByText(/Aucun checkpoint/i);
    expect(screen.queryByRole('button', { name: /Ajouter/i })).not.toBeInTheDocument();
  });

  it('ouvre le dialog de création au clic sur Ajouter', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue([] as any);
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    await user.click(await screen.findByRole('button', { name: /Ajouter/i }));
    expect(screen.getByTestId('create-checkpoint-dialog')).toBeInTheDocument();
  });

  it('affiche les boutons edit et delete pour un checkpoint DRAFT', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummaryWithDraft as any);
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    expect(await screen.findByText('Accueil')).toBeInTheDocument();
    expect(document.querySelector('button svg.lucide-pencil')?.closest('button')).toBeTruthy();
    expect(document.querySelector('button svg.lucide-trash-2')?.closest('button')).toBeTruthy();
  });

  it('n\'affiche pas les boutons delete pour un checkpoint CLOSED ou ACTIVE', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummary as any);
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    await screen.findByText('Départ');
    // lucide-trash-2 n'est présent que sur les checkpoints DRAFT
    expect(document.querySelectorAll('button svg.lucide-trash-2')).toHaveLength(0);
  });

  it('appelle deleteCheckpoint après confirmation', async () => {
    const user = userEvent.setup();
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummaryWithDraft as any);
    vi.mocked(tripApi.deleteCheckpoint).mockResolvedValue(undefined);
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    await screen.findByText('Accueil');
    const deleteBtn = document.querySelector('button svg.lucide-trash-2')?.closest('button') as HTMLElement;
    await user.click(deleteBtn);
    expect(vi.mocked(tripApi.deleteCheckpoint)).toHaveBeenCalledWith('cp-draft');
  });

  it('n\'appelle pas deleteCheckpoint si confirmation refusée', async () => {
    const user = userEvent.setup();
    vi.spyOn(window, 'confirm').mockReturnValue(false);
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummaryWithDraft as any);
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    await screen.findByText('Accueil');
    const deleteBtn = document.querySelector('button svg.lucide-trash-2')?.closest('button') as HTMLElement;
    await user.click(deleteBtn);
    expect(vi.mocked(tripApi.deleteCheckpoint)).not.toHaveBeenCalled();
  });

  it('ouvre le dialog d\'édition au clic sur le bouton edit', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.getById).mockResolvedValue(mockTrip as any);
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue(mockCheckpointsSummaryWithDraft as any);
    render(<TripDetailScreen />);
    await screen.findByText('Bruges');
    await user.click(screen.getByText('Points de contrôle'));
    await screen.findByText('Accueil');
    // Le premier lucide-pencil est "Modifier le voyage" (header) — on prend le dernier
    const pencilBtns = document.querySelectorAll('button svg.lucide-pencil');
    const editBtn = pencilBtns[pencilBtns.length - 1]?.closest('button') as HTMLElement;
    await user.click(editBtn);
    expect(screen.getByTestId('edit-checkpoint-dialog')).toBeInTheDocument();
  });
});
