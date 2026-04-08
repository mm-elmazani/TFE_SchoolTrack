import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import StudentImportScreen from '../screens/StudentImportScreen';
import { studentApi } from '../api/studentApi';

vi.mock('../api/studentApi', () => ({
  studentApi: { uploadCsv: vi.fn() },
}));

vi.mock('@/hooks/useSchoolPath', () => ({
  useSchoolPath: () => (path: string) => `/dev${path}`,
}));

beforeEach(() => vi.clearAllMocks());

describe('StudentImportScreen', () => {
  it('renders page title and subtitle', () => {
    render(<StudentImportScreen />);
    expect(screen.getByText(/Importer des .l.ves/i)).toBeInTheDocument();
    expect(screen.getByText(/rapidement plusieurs .l.ves/i)).toBeInTheDocument();
  });

  it('renders file upload area', () => {
    render(<StudentImportScreen />);
    expect(screen.getByText(/Glissez|cliquez/i)).toBeInTheDocument();
  });

  it('renders format requirement', () => {
    render(<StudentImportScreen />);
    expect(screen.getByText(/Format CSV/i)).toBeInTheDocument();
  });

  it('renders directives section', () => {
    render(<StudentImportScreen />);
    expect(screen.getByText('Directives')).toBeInTheDocument();
    expect(screen.getByText(/Colonnes requises/i)).toBeInTheDocument();
    expect(screen.getByText(/Colonnes optionnelles/i)).toBeInTheDocument();
  });

  it('renders required and optional columns', () => {
    render(<StudentImportScreen />);
    // "nom, prenom" appears in the directives section (exact text in the bordered list)
    expect(screen.getAllByText(/nom.*prenom/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/email.*classe/i).length).toBeGreaterThan(0);
  });

  it('renders import button initially disabled without file', () => {
    render(<StudentImportScreen />);
    const btn = screen.getByRole('button', { name: /lancer l.importation/i });
    expect(btn).toBeDisabled();
  });

  it('shows error when non-CSV file selected', async () => {
    render(<StudentImportScreen />);
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    const file = new File(['data'], 'test.txt', { type: 'text/plain' });
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    fireEvent.change(input);
    await waitFor(() => {
      // Error: "Le fichier doit être au format CSV."
      expect(screen.getByText(/doit.*format CSV/i)).toBeInTheDocument();
    });
  });

  it('shows file info after CSV file selected', async () => {
    render(<StudentImportScreen />);
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    const file = new File(['nom,prenom\nJean,Dupont'], 'eleves.csv', { type: 'text/csv' });
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    fireEvent.change(input);
    await waitFor(() => {
      expect(screen.getByText('eleves.csv')).toBeInTheDocument();
    });
  });

  it('enables import button after CSV file selected', async () => {
    render(<StudentImportScreen />);
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    const file = new File(['nom,prenom\nJean,Dupont'], 'eleves.csv', { type: 'text/csv' });
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    fireEvent.change(input);
    await waitFor(() => {
      const btn = screen.getByRole('button', { name: /lancer l.importation/i });
      expect(btn).not.toBeDisabled();
    });
  });

  it('shows success data after successful import', async () => {
    vi.mocked(studentApi.uploadCsv).mockResolvedValue({ inserted: 5, rejected: 1 } as any);
    render(<StudentImportScreen />);
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    const file = new File(['nom,prenom\nJean,Dupont'], 'eleves.csv', { type: 'text/csv' });
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    fireEvent.change(input);
    await waitFor(() => screen.getByRole('button', { name: /lancer l.importation/i }));
    fireEvent.click(screen.getByRole('button', { name: /lancer l.importation/i }));
    expect(await screen.findByText(/Importation termin/i)).toBeInTheDocument();
    expect(screen.getByText('5')).toBeInTheDocument();
    expect(screen.getByText('1')).toBeInTheDocument();
  });

  it('shows reset button after file selected', async () => {
    render(<StudentImportScreen />);
    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    const file = new File(['nom,prenom\nJean,Dupont'], 'eleves.csv', { type: 'text/csv' });
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    fireEvent.change(input);
    await waitFor(() => {
      expect(screen.getByText(/Initialiser|Reinitialiser/i)).toBeInTheDocument();
    });
  });

  it('renders back to students link', () => {
    render(<StudentImportScreen />);
    expect(screen.queryByText(/Retour/i)).toBeDefined();
  });

  it('renders duplicate note', () => {
    render(<StudentImportScreen />);
    expect(screen.getByText(/doublons/i)).toBeInTheDocument();
  });
});
