import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '../../../test/test-utils';
import TokenManagementScreen from '../screens/TokenManagementScreen';
import { tripApi } from '@/features/trips/api/tripApi';
import { tokenApi } from '../api/tokenApi';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('@/features/trips/api/tripApi', () => ({
  tripApi: { getAll: vi.fn() },
}));

vi.mock('../api/tokenApi', () => ({
  tokenApi: {
    getTripStudents: vi.fn(),
    releaseTripTokens: vi.fn(),
    releaseAssignment: vi.fn(),
    sendQrEmails: vi.fn(),
    getExportUrl: vi.fn(() => '/export'),
  },
}));

vi.mock('../components/AssignTokenDialog', () => ({
  AssignTokenDialog: () => null,
}));

const mockTrips = [
  { id: 't1', destination: 'Paris', date: '2026-05-10', description: 'Voyage scolaire', status: 'ACTIVE', total_students: 25, classes: [], created_at: '', updated_at: '' },
  { id: 't2', destination: 'Bruges', date: '2026-06-15', description: 'Excursion', status: 'PLANNED', total_students: 15, classes: [], created_at: '', updated_at: '' },
  { id: 't3', destination: 'Archive Trip', date: '2025-01-01', description: '', status: 'ARCHIVED', total_students: 10, classes: [], created_at: '', updated_at: '' },
] as any;

const mockTripStudents = {
  trip_id: 't1',
  students: [
    {
      id: 's1', first_name: 'Jean', last_name: 'Dupont', is_assigned: true,
      assignment_id: 1, token_uid: 'NFC-001', assignment_type: 'NFC_PHYSICAL' as const, assigned_at: '2026-01-01',
      secondary_assignment_id: null, secondary_token_uid: null, secondary_assignment_type: null, secondary_assigned_at: null,
    },
    {
      id: 's2', first_name: 'Marie', last_name: 'Martin', is_assigned: false,
      assignment_id: null, token_uid: null, assignment_type: null, assigned_at: null,
      secondary_assignment_id: null, secondary_token_uid: null, secondary_assignment_type: null, secondary_assigned_at: null,
    },
  ],
  total: 2,
  assigned: 1,
  unassigned: 1,
  assigned_digital: 0,
};

beforeEach(() => {
  vi.clearAllMocks();
  useAuthStore.setState({
    token: 'test',
    user: { id: '1', email: 'admin@test.be', first_name: 'Admin', last_name: 'Test', role: 'DIRECTION' },
  });
});

describe('TokenManagementScreen', () => {
  it('renders loading state', () => {
    vi.mocked(tripApi.getAll).mockReturnValue(new Promise(() => {}));
    render(<TokenManagementScreen />);
    expect(screen.getByText(/Chargement des voyages/i)).toBeInTheDocument();
  });

  it('renders error state when trips fail to load', async () => {
    vi.mocked(tripApi.getAll).mockRejectedValue(new Error('API Error'));
    render(<TokenManagementScreen />);
    expect(await screen.findByText('Erreur de chargement')).toBeInTheDocument();
    expect(screen.getByText(/Impossible de r.*la liste des voyages/i)).toBeInTheDocument();
  });

  it('renders page title and description', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TokenManagementScreen />);
    expect(await screen.findByText('Gestion des Bracelets')).toBeInTheDocument();
    expect(screen.getByText(/supports NFC\/QR/i)).toBeInTheDocument();
  });

  it('renders trip list (excluding archived)', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TokenManagementScreen />);
    expect(await screen.findByText('Paris')).toBeInTheDocument();
    expect(screen.getByText('Bruges')).toBeInTheDocument();
    expect(screen.queryByText('Archive Trip')).not.toBeInTheDocument();
  });

  it('renders empty state when no trip selected', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TokenManagementScreen />);
    expect(await screen.findByText(/lectionnez un voyage/i)).toBeInTheDocument();
  });

  it('renders student table after trip selection', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);

    const parisBtn = await screen.findByText('Paris');
    fireEvent.click(parisBtn);

    expect(await screen.findByText('Dupont')).toBeInTheDocument();
    expect(screen.getByText('Martin')).toBeInTheDocument();
  });

  it('renders stats cards after trip selection', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);

    const parisBtn = await screen.findByText('Paris');
    fireEvent.click(parisBtn);

    await screen.findByText('Dupont');
    expect(screen.getByText('Physiques')).toBeInTheDocument();
    expect(screen.getByText('QR Digitaux')).toBeInTheDocument();
    expect(screen.getByText('Non assignes')).toBeInTheDocument();
  });

  it('renders token UID for assigned students', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);

    fireEvent.click(await screen.findByText('Paris'));
    expect(await screen.findByText('NFC-001')).toBeInTheDocument();
  });

  it('renders action buttons for admin', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);

    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    expect(screen.getByText('Export CSV')).toBeInTheDocument();
    expect(screen.getByText('Envoyer QR')).toBeInTheDocument();
  });

  it('renders empty student list message', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue({
      trip_id: 't1', students: [], total: 0, assigned: 0, unassigned: 0, assigned_digital: 0,
    });
    render(<TokenManagementScreen />);

    fireEvent.click(await screen.findByText('Paris'));
    expect(await screen.findByText(/Aucun eleve/i)).toBeInTheDocument();
  });

  it('renders no trips available message', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue([
      { id: 't3', destination: 'Archive Trip', date: '2025-01-01', description: '', status: 'ARCHIVED', total_students: 10, classes: [], created_at: '', updated_at: '' },
    ] as any);
    render(<TokenManagementScreen />);
    expect(await screen.findByText(/Aucun voyage disponible/i)).toBeInTheDocument();
  });

  it('renders search bar after trip selection', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);

    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    expect(screen.getByPlaceholderText(/Rechercher/i)).toBeInTheDocument();
  });

  it('renders voyages sidebar title', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    render(<TokenManagementScreen />);
    expect(await screen.findByText('Voyages')).toBeInTheDocument();
  });

  it('clicks Assigner button for unassigned student', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Martin');
    // Martin has no token → button shows "Assigner"
    fireEvent.click(screen.getByText('Assigner'));
    expect(screen.getByText('Martin')).toBeInTheDocument();
  });

  it('clicks Libérer Tout with confirm and shows feedback banner', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    vi.mocked(tokenApi.releaseTripTokens).mockResolvedValue({ released_count: 1 } as any);
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    fireEvent.click(screen.getByText('Libérer Tout'));
    expect(await screen.findByText(/bracelets libérés/i)).toBeInTheDocument();
  });

  it('dismisses action feedback banner by clicking X', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    vi.mocked(tokenApi.releaseTripTokens).mockResolvedValue({ released_count: 1 } as any);
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    fireEvent.click(screen.getByText('Libérer Tout'));
    await screen.findByText(/bracelets libérés/i);
    // Click the X dismiss button on the feedback banner
    const dismissBtn = document.querySelector('svg.lucide-x')?.closest('button');
    if (dismissBtn) fireEvent.click(dismissBtn as HTMLElement);
    expect(screen.queryByText(/bracelets libérés/i)).not.toBeInTheDocument();
  });

  it('clicks Envoyer QR with confirm and shows success feedback', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    vi.mocked(tokenApi.sendQrEmails).mockResolvedValue({ sent_count: 2 } as any);
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    fireEvent.click(screen.getByText('Envoyer QR'));
    expect(await screen.findByText(/emails envoyés/i)).toBeInTheDocument();
  });

  it('uses search filter to find students', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    fireEvent.change(screen.getByPlaceholderText(/Rechercher/i), { target: { value: 'Dupont' } });
    expect(screen.getByText('Dupont')).toBeInTheDocument();
  });

  it('clicks Desassigner button with confirm for assigned student', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    vi.mocked(tokenApi.releaseAssignment).mockResolvedValue({ token_uid: 'NFC-001', student_name: 'Jean Dupont' } as any);
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    fireEvent.click(screen.getByText('Desassigner'));
    expect(await screen.findByText(/NFC-001/i)).toBeInTheDocument();
  });

  it('renders NFC badge for NFC_PHYSICAL assignment type', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    expect(screen.getByText('NFC')).toBeInTheDocument();
  });

  it('clicks +QR button to add digital QR for assigned student', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    // Dupont has token_uid but no secondary → +QR button appears
    fireEvent.click(screen.getByText(/\+ QR/i));
    expect(screen.getByText('Dupont')).toBeInTheDocument();
  });

  it('clicks refresh button when trip is selected', async () => {
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    const refreshBtn = document.querySelector('svg.lucide-refresh-cw')?.closest('button');
    if (refreshBtn) fireEvent.click(refreshBtn as HTMLElement);
    expect(screen.getByText('Dupont')).toBeInTheDocument();
  });

  it('shows error feedback when Libérer Tout mutation fails', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    vi.mocked(tokenApi.releaseTripTokens).mockRejectedValue(new Error('fail'));
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    fireEvent.click(screen.getByText('Libérer Tout'));
    expect(await screen.findByText(/Erreur lors de la lib/i)).toBeInTheDocument();
  });

  it('shows error feedback when Envoyer QR mutation fails', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    vi.mocked(tripApi.getAll).mockResolvedValue(mockTrips);
    vi.mocked(tokenApi.getTripStudents).mockResolvedValue(mockTripStudents);
    vi.mocked(tokenApi.sendQrEmails).mockRejectedValue(new Error('fail'));
    render(<TokenManagementScreen />);
    fireEvent.click(await screen.findByText('Paris'));
    await screen.findByText('Dupont');
    fireEvent.click(screen.getByText('Envoyer QR'));
    expect(await screen.findByText(/Erreur lors de l.envoi/i)).toBeInTheDocument();
  });
});
