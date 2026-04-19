import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '../../../test/test-utils';
import userEvent from '@testing-library/user-event';
import { CreateCheckpointDialog } from '../components/CreateCheckpointDialog';
import { tripApi } from '../api/tripApi';

vi.mock('../api/tripApi', () => ({
  tripApi: { createCheckpoint: vi.fn() },
}));

const defaultProps = {
  tripId: 'trip-1',
  open: true,
  onOpenChange: vi.fn(),
};

beforeEach(() => {
  vi.clearAllMocks();
});

describe('CreateCheckpointDialog', () => {
  it('affiche les champs nom et description', () => {
    render(<CreateCheckpointDialog {...defaultProps} />);
    expect(screen.getByLabelText(/Nom/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Description/i)).toBeInTheDocument();
  });

  it('affiche le bouton Créer', () => {
    render(<CreateCheckpointDialog {...defaultProps} />);
    expect(screen.getByRole('button', { name: /Créer/i })).toBeInTheDocument();
  });

  it('affiche une erreur de validation si le nom est vide', async () => {
    const user = userEvent.setup();
    render(<CreateCheckpointDialog {...defaultProps} />);
    await user.click(screen.getByRole('button', { name: /Créer/i }));
    expect(await screen.findByText(/Le nom est requis/i)).toBeInTheDocument();
  });

  it('appelle createCheckpoint avec les bonnes données', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.createCheckpoint).mockResolvedValue({} as any);
    render(<CreateCheckpointDialog {...defaultProps} />);
    await user.type(screen.getByLabelText(/Nom/i), 'Entrée musée');
    await user.type(screen.getByLabelText(/Description/i), 'Vérifier les présences');
    await user.click(screen.getByRole('button', { name: /Créer/i }));
    await waitFor(() => {
      expect(vi.mocked(tripApi.createCheckpoint)).toHaveBeenCalledWith('trip-1', {
        name: 'Entrée musée',
        description: 'Vérifier les présences',
      });
    });
  });

  it('ferme le dialog après une création réussie', async () => {
    const user = userEvent.setup();
    const onOpenChange = vi.fn();
    vi.mocked(tripApi.createCheckpoint).mockResolvedValue({} as any);
    render(<CreateCheckpointDialog {...defaultProps} onOpenChange={onOpenChange} />);
    await user.type(screen.getByLabelText(/Nom/i), 'Sortie');
    await user.click(screen.getByRole('button', { name: /Créer/i }));
    await waitFor(() => expect(onOpenChange).toHaveBeenCalledWith(false));
  });

  it('affiche une erreur serveur en cas d\'échec', async () => {
    const user = userEvent.setup();
    vi.mocked(tripApi.createCheckpoint).mockRejectedValue(new Error('Voyage terminé'));
    render(<CreateCheckpointDialog {...defaultProps} />);
    await user.type(screen.getByLabelText(/Nom/i), 'Sortie');
    await user.click(screen.getByRole('button', { name: /Créer/i }));
    expect(await screen.findByText('Voyage terminé')).toBeInTheDocument();
  });

  it('ferme et réinitialise sur Annuler', async () => {
    const user = userEvent.setup();
    const onOpenChange = vi.fn();
    render(<CreateCheckpointDialog {...defaultProps} onOpenChange={onOpenChange} />);
    await user.type(screen.getByLabelText(/Nom/i), 'Test');
    await user.click(screen.getByRole('button', { name: /Annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });
});
