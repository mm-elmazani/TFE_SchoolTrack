import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '../../../test/test-utils';
import userEvent from '@testing-library/user-event';
import { EditCheckpointDialog } from '../components/EditCheckpointDialog';
import { tripApi } from '../api/tripApi';

vi.mock('../api/tripApi', () => ({
  tripApi: { updateCheckpoint: vi.fn() },
}));

const mockCheckpoint = {
  id: 'cp-1',
  name: 'Entrée musée',
  description: 'Vérifier les présences',
  sequence_order: 1,
  status: 'DRAFT',
  created_at: null,
  started_at: null,
  closed_at: null,
  created_by_name: null,
  scan_count: 0,
  student_count: 0,
  duration_minutes: null,
};

const defaultProps = {
  tripId: 'trip-1',
  checkpoint: mockCheckpoint,
  open: true,
  onOpenChange: vi.fn(),
};

beforeEach(() => {
  vi.clearAllMocks();
});

describe('EditCheckpointDialog', () => {
  it('affiche le formulaire pré-rempli avec les valeurs du checkpoint', async () => {
    render(<EditCheckpointDialog {...defaultProps} />);
    expect(await screen.findByDisplayValue('Entrée musée')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Vérifier les présences')).toBeInTheDocument();
  });

  it('affiche le bouton Enregistrer', () => {
    render(<EditCheckpointDialog {...defaultProps} />);
    expect(screen.getByRole('button', { name: /Enregistrer/i })).toBeInTheDocument();
  });

  it('affiche une erreur de validation si le nom est vidé', async () => {
    const user = userEvent.setup();
    render(<EditCheckpointDialog {...defaultProps} />);
    const input = await screen.findByDisplayValue('Entrée musée');
    await user.clear(input);
    await user.click(screen.getByRole('button', { name: /Enregistrer/i }));
    expect(await screen.findByText(/Le nom est requis/i)).toBeInTheDocument();
  });

  it('appelle updateCheckpoint avec les nouvelles valeurs', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.updateCheckpoint).mockResolvedValue({} as any);
    render(<EditCheckpointDialog {...defaultProps} />);
    const input = await screen.findByDisplayValue('Entrée musée');
    await user.clear(input);
    await user.type(input, 'Sortie musée');
    await user.click(screen.getByRole('button', { name: /Enregistrer/i }));
    await waitFor(() => {
      expect(vi.mocked(tripApi.updateCheckpoint)).toHaveBeenCalledWith('cp-1', expect.objectContaining({ name: 'Sortie musée' }));
    });
  });

  it('ferme le dialog après une modification réussie', async () => {
    const user = userEvent.setup();
    const onOpenChange = vi.fn();
    vi.mocked(tripApi.updateCheckpoint).mockResolvedValue({} as any);
    render(<EditCheckpointDialog {...defaultProps} onOpenChange={onOpenChange} />);
    await screen.findByDisplayValue('Entrée musée');
    await user.click(screen.getByRole('button', { name: /Enregistrer/i }));
    await waitFor(() => expect(onOpenChange).toHaveBeenCalledWith(false));
  });

  it('affiche une erreur serveur en cas d\'échec', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.updateCheckpoint).mockRejectedValue(new Error('Statut invalide'));
    render(<EditCheckpointDialog {...defaultProps} />);
    await screen.findByDisplayValue('Entrée musée');
    await user.click(screen.getByRole('button', { name: /Enregistrer/i }));
    expect(await screen.findByText('Statut invalide')).toBeInTheDocument();
  });

  it('ne rend rien quand checkpoint est null', () => {
    render(<EditCheckpointDialog {...defaultProps} checkpoint={null} open={false} />);
    expect(screen.queryByRole('button', { name: /Enregistrer/i })).not.toBeInTheDocument();
  });
});
