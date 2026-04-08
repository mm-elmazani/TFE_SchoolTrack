import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { CreateStudentDialog } from '../components/CreateStudentDialog';
import { classApi } from '@/features/classes/api/classApi';
import { studentApi } from '../api/studentApi';

vi.mock('@/features/classes/api/classApi', () => ({
  classApi: { getAll: vi.fn() },
}));

vi.mock('../api/studentApi', () => ({
  studentApi: { create: vi.fn(), uploadPhoto: vi.fn() },
}));

const mockClasses = [
  { id: 'c1', name: '5ème A', year: '2025-2026', nb_students: 25, nb_teachers: 2, created_at: '', updated_at: '' },
];

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(classApi.getAll).mockResolvedValue([]);
});

describe('CreateStudentDialog', () => {
  it('renders dialog when open', () => {
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /sauvegarder/i })).toBeInTheDocument();
  });

  it('renders dialog title', () => {
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Ajouter un élève/i)).toBeInTheDocument();
  });

  it('renders dialog subtitle', () => {
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/profil élève/i)).toBeInTheDocument();
  });

  it('renders form labels', () => {
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Nom')).toBeInTheDocument();
    expect(screen.getByText('Prénom')).toBeInTheDocument();
  });

  it('renders email and phone fields', () => {
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Email \(optionnel\)/i)).toBeInTheDocument();
    expect(screen.getByText(/Téléphone \(optionnel\)/i)).toBeInTheDocument();
  });

  it('renders photo upload option', () => {
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Photo \(optionnel\)/i)).toBeInTheDocument();
  });

  it('renders class selector with loaded classes', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    expect(await screen.findByText('5ème A (2025-2026)')).toBeInTheDocument();
  });

  it('renders save and cancel buttons', () => {
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /sauvegarder/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /annuler/i })).toBeInTheDocument();
  });

  it('closes on cancel button click', () => {
    const onOpenChange = vi.fn();
    render(<CreateStudentDialog open={true} onOpenChange={onOpenChange} />);
    fireEvent.click(screen.getByRole('button', { name: /annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it('calls studentApi.create on submit with valid data', async () => {
    vi.mocked(studentApi.create).mockResolvedValue({ id: 's1', first_name: 'Jean', last_name: 'Dupont' } as any);
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    fireEvent.change(screen.getByPlaceholderText(/ex: Dupont/i), { target: { value: 'Dupont' } });
    fireEvent.change(screen.getByPlaceholderText(/ex: Jean/i), { target: { value: 'Jean' } });
    fireEvent.click(screen.getByRole('button', { name: /sauvegarder/i }));
    await waitFor(() => expect(studentApi.create).toHaveBeenCalled());
  });

  it('shows server error on API failure', async () => {
    vi.mocked(studentApi.create).mockRejectedValue({
      response: { data: { detail: 'Email déjà utilisé' } },
    });
    render(<CreateStudentDialog open={true} onOpenChange={vi.fn()} />);
    fireEvent.change(screen.getByPlaceholderText(/ex: Dupont/i), { target: { value: 'Dupont' } });
    fireEvent.change(screen.getByPlaceholderText(/ex: Jean/i), { target: { value: 'Jean' } });
    fireEvent.click(screen.getByRole('button', { name: /sauvegarder/i }));
    expect(await screen.findByText('Email déjà utilisé')).toBeInTheDocument();
  });

  it('does not render when closed', () => {
    render(<CreateStudentDialog open={false} onOpenChange={vi.fn()} />);
    expect(screen.queryByText(/Ajouter un élève/i)).not.toBeInTheDocument();
  });
});
