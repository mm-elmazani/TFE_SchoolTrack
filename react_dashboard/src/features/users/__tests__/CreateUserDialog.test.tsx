import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { CreateUserDialog } from '../components/CreateUserDialog';
import { userApi } from '../api/userApi';

vi.mock('../api/userApi', () => ({
  userApi: { create: vi.fn(), getAll: vi.fn(), delete: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('CreateUserDialog', () => {
  it('renders dialog when open', () => {
    render(<CreateUserDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Ajouter un utilisateur')).toBeInTheDocument();
  });

  it('renders email and password fields', () => {
    render(<CreateUserDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
  });

  it('renders form labels', () => {
    render(<CreateUserDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Nom')).toBeInTheDocument();
    expect(screen.getByText(/Pr.nom/i)).toBeInTheDocument();
    expect(screen.getByText(/Mot de passe/i)).toBeInTheDocument();
  });

  it('renders role selector label', () => {
    render(<CreateUserDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getAllByText(/R.le/i).length).toBeGreaterThan(0);
  });

  it('renders create and cancel buttons', () => {
    render(<CreateUserDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /Cr.er le compte/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Annuler/i })).toBeInTheDocument();
  });

  it('renders dialog subtitle', () => {
    render(<CreateUserDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/nouveau compte/i)).toBeInTheDocument();
  });

  it('renders password requirements hint', () => {
    render(<CreateUserDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Min 8/i)).toBeInTheDocument();
  });

  it('closes on cancel button click', () => {
    const onOpenChange = vi.fn();
    render(<CreateUserDialog open={true} onOpenChange={onOpenChange} />);
    fireEvent.click(screen.getByRole('button', { name: /Annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it('calls userApi.create on submit with valid data', async () => {
    vi.mocked(userApi.create).mockResolvedValue({ id: 'u1' } as any);
    render(<CreateUserDialog open={true} onOpenChange={vi.fn()} />);
    fireEvent.change(screen.getByPlaceholderText(/ex: Dupont/i), { target: { value: 'Dupont' } });
    fireEvent.change(screen.getByPlaceholderText(/ex: Jean/i), { target: { value: 'Jean' } });
    fireEvent.change(screen.getByLabelText(/email/i), { target: { value: 'jean.dupont@test.be' } });
    fireEvent.change(screen.getByLabelText(/mot de passe/i), { target: { value: 'Password1!' } });
    fireEvent.click(screen.getByRole('button', { name: /Cr.er le compte/i }));
    await waitFor(() => expect(userApi.create).toHaveBeenCalled());
  });

  it('shows server error on API failure', async () => {
    vi.mocked(userApi.create).mockRejectedValue({
      response: { data: { detail: 'Email déjà utilisé' } },
    });
    render(<CreateUserDialog open={true} onOpenChange={vi.fn()} />);
    fireEvent.change(screen.getByPlaceholderText(/ex: Dupont/i), { target: { value: 'Dupont' } });
    fireEvent.change(screen.getByPlaceholderText(/ex: Jean/i), { target: { value: 'Jean' } });
    fireEvent.change(screen.getByLabelText(/email/i), { target: { value: 'jean.dupont@test.be' } });
    fireEvent.change(screen.getByLabelText(/mot de passe/i), { target: { value: 'Password1!' } });
    fireEvent.click(screen.getByRole('button', { name: /Cr.er le compte/i }));
    expect(await screen.findByText('Email déjà utilisé')).toBeInTheDocument();
  });

  it('does not render when closed', () => {
    render(<CreateUserDialog open={false} onOpenChange={vi.fn()} />);
    expect(screen.queryByText('Ajouter un utilisateur')).not.toBeInTheDocument();
  });
});
