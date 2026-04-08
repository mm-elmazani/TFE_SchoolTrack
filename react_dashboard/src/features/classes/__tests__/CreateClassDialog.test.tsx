import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { CreateClassDialog } from '../components/CreateClassDialog';
import { classApi } from '../api/classApi';

vi.mock('../api/classApi', () => ({
  classApi: { create: vi.fn(), getAll: vi.fn() },
}));

beforeEach(() => vi.clearAllMocks());

describe('CreateClassDialog', () => {
  it('renders dialog when open', () => {
    render(<CreateClassDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Sauvegarder/i)).toBeInTheDocument();
  });

  it('renders dialog title', () => {
    render(<CreateClassDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Créer une classe')).toBeInTheDocument();
  });

  it('renders dialog subtitle', () => {
    render(<CreateClassDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/nouvelle classe/i)).toBeInTheDocument();
  });

  it('renders form labels', () => {
    render(<CreateClassDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Nom de la classe')).toBeInTheDocument();
    expect(screen.getByText(/Année scolaire/i)).toBeInTheDocument();
  });

  it('renders name and year input placeholders', () => {
    render(<CreateClassDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByPlaceholderText(/5ème A/i)).toBeInTheDocument();
    expect(screen.getByPlaceholderText(/2025-2026/i)).toBeInTheDocument();
  });

  it('renders save and cancel buttons', () => {
    render(<CreateClassDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /sauvegarder/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /annuler/i })).toBeInTheDocument();
  });

  it('closes on cancel button click', () => {
    const onOpenChange = vi.fn();
    render(<CreateClassDialog open={true} onOpenChange={onOpenChange} />);
    fireEvent.click(screen.getByRole('button', { name: /annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it('calls classApi.create on submit with valid data', async () => {
    vi.mocked(classApi.create).mockResolvedValue({
      id: 'c1', name: '5ème A', year: '', nb_students: 0, nb_teachers: 0, created_at: '', updated_at: '',
    });
    render(<CreateClassDialog open={true} onOpenChange={vi.fn()} />);
    fireEvent.change(screen.getByPlaceholderText(/5ème A/i), { target: { value: '5ème A' } });
    fireEvent.click(screen.getByRole('button', { name: /sauvegarder/i }));
    await waitFor(() => expect(classApi.create).toHaveBeenCalled());
  });

  it('shows server error on API failure', async () => {
    vi.mocked(classApi.create).mockRejectedValue({
      response: { data: { detail: 'Classe déjà existante' } },
    });
    render(<CreateClassDialog open={true} onOpenChange={vi.fn()} />);
    fireEvent.change(screen.getByPlaceholderText(/5ème A/i), { target: { value: 'Duplicate' } });
    fireEvent.click(screen.getByRole('button', { name: /sauvegarder/i }));
    expect(await screen.findByText('Classe déjà existante')).toBeInTheDocument();
  });

  it('does not render when closed', () => {
    render(<CreateClassDialog open={false} onOpenChange={vi.fn()} />);
    expect(screen.queryByText('Créer une classe')).not.toBeInTheDocument();
  });
});
