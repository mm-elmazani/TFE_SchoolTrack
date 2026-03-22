import { useState, useRef } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { studentApi } from '../api/studentApi';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Link } from 'react-router-dom';
import { Upload, FileText, X, CheckCircle2, AlertCircle, ArrowLeft, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';

export default function StudentImportScreen() {
  const [file, setFile] = useState<File | null>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successData, setSuccessData] = useState<{ inserted: number, rejected: number } | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const queryClient = useQueryClient();

  const validateAndSetFile = (selectedFile: File) => {
    if (!selectedFile.name.endsWith('.csv')) {
      setErrorMsg('Le fichier doit être au format CSV.');
      setFile(null);
      return false;
    }
    setFile(selectedFile);
    setErrorMsg(null);
    setSuccessData(null);
    return true;
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      validateAndSetFile(e.target.files[0]);
    }
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  };

  const handleDragLeave = () => {
    setIsDragging(false);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      validateAndSetFile(e.dataTransfer.files[0]);
    }
  };

  const importMutation = useMutation({
    mutationFn: studentApi.uploadCsv,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['students'] });
      setSuccessData({ inserted: data.inserted, rejected: data.rejected });
      setFile(null);
      if (fileInputRef.current) fileInputRef.current.value = '';
    },
    onError: (error: any) => {
      setErrorMsg(error.response?.data?.detail || 'Une erreur est survenue lors de l\'importation');
      setSuccessData(null);
    },
  });

  const handleUpload = () => {
    if (!file) {
      setErrorMsg('Veuillez sélectionner un fichier CSV.');
      return;
    }
    importMutation.mutate(file);
  };

  const clearFile = () => {
    setFile(null);
    if (fileInputRef.current) fileInputRef.current.value = '';
    setErrorMsg(null);
  };

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <div className="flex items-center gap-4">
        <Link to="/students">
          <Button variant="ghost" size="sm" className="rounded-full w-10 h-10 p-0 hover:bg-blue-50">
            <ArrowLeft className="w-5 h-5 text-schooltrack-primary" />
          </Button>
        </Link>
        <div className="flex flex-col gap-1">
          <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary">Importer des élèves</h2>
          <p className="text-slate-500">Ajoutez rapidement plusieurs élèves via un fichier CSV.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
        <div className="md:col-span-2 space-y-6">
          {successData && (
            <div className="p-4 bg-green-50 text-schooltrack-success border border-green-100 rounded-xl text-sm flex items-start gap-3 animate-in fade-in slide-in-from-top-2">
              <CheckCircle2 className="w-5 h-5 mt-0.5 flex-shrink-0" />
              <div className="flex-1">
                <p className="font-bold text-base">Importation terminée !</p>
                <div className="mt-2 grid grid-cols-2 gap-4">
                  <div className="bg-white/50 p-2 rounded-lg border border-green-100">
                    <p className="text-xs uppercase tracking-wider opacity-70">Insérés</p>
                    <p className="text-xl font-bold">{successData.inserted}</p>
                  </div>
                  <div className="bg-white/50 p-2 rounded-lg border border-green-100">
                    <p className="text-xs uppercase tracking-wider opacity-70">Rejetés</p>
                    <p className="text-xl font-bold">{successData.rejected}</p>
                  </div>
                </div>
                <p className="mt-3 text-xs opacity-80 italic">Les élèves rejetés sont probablement des doublons déjà présents dans le système.</p>
              </div>
              <button onClick={() => setSuccessData(null)} className="text-schooltrack-success hover:opacity-70 transition-colors">
                <X className="w-4 h-4" />
              </button>
            </div>
          )}

          <Card 
            className={cn(
              "border-dashed border-2 transition-all duration-300 overflow-hidden shadow-sm",
              isDragging ? "border-schooltrack-action bg-blue-50/50 scale-[1.01]" : "border-slate-200 bg-white",
              file ? "border-solid border-slate-200" : ""
            )}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
          >
            <CardContent className="p-0">
              {!file ? (
                <div 
                  className="p-12 flex flex-col items-center justify-center gap-4 text-center cursor-pointer group"
                  onClick={() => fileInputRef.current?.click()}
                >
                  <div className={cn(
                    "w-16 h-16 rounded-2xl shadow-sm flex items-center justify-center transition-all duration-300",
                    isDragging ? "bg-schooltrack-action text-white scale-110 shadow-lg shadow-blue-200" : "bg-slate-50 text-slate-400 group-hover:bg-blue-50 group-hover:text-schooltrack-action group-hover:shadow-md"
                  )}>
                    <Upload className={cn("w-8 h-8", isDragging && "animate-bounce")} />
                  </div>
                  <div>
                    <p className="text-lg font-semibold text-slate-900">
                      {isDragging ? "Relâchez pour ajouter" : "Glissez-déposez ou cliquez ici"}
                    </p>
                    <p className="text-sm text-slate-500 mt-1">Format CSV uniquement (nom, prenom, email, classe)</p>
                  </div>
                  <input
                    ref={fileInputRef}
                    id="csv_file"
                    type="file"
                    accept=".csv"
                    className="hidden"
                    onChange={handleFileChange}
                  />
                </div>
              ) : (
                <div className="p-8 flex items-center justify-between bg-white animate-in fade-in zoom-in duration-300">
                  <div className="flex items-center gap-4">
                    <div className="w-12 h-12 bg-schooltrack-primary rounded-lg flex items-center justify-center text-white shadow-lg shadow-blue-900/20">
                      <FileText className="w-6 h-6" />
                    </div>
                    <div>
                      <p className="font-semibold text-slate-900 truncate max-w-[200px]">{file.name}</p>
                      <p className="text-xs text-slate-400">{(file.size / 1024).toFixed(2)} KB</p>
                    </div>
                  </div>
                  <Button 
                    variant="ghost" 
                    size="sm" 
                    onClick={(e) => { e.stopPropagation(); clearFile(); }}
                    className="text-slate-400 hover:text-schooltrack-error hover:bg-red-50 rounded-full w-10 h-10 p-0"
                  >
                    <X className="w-5 h-5" />
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>

          {errorMsg && (
            <div className="p-4 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm flex items-start gap-3 animate-in fade-in slide-in-from-top-2">
              <AlertCircle className="w-5 h-5 mt-0.5 flex-shrink-0" />
              <span>{errorMsg}</span>
            </div>
          )}

          <div className="flex justify-end gap-3">
            <Button
              variant="outline"
              onClick={clearFile}
              disabled={importMutation.isPending || !file}
              className="h-11 px-6 rounded-xl border-slate-200 hover:bg-slate-50"
            >
              Réinitialiser
            </Button>
            <Button 
              onClick={handleUpload} 
              disabled={importMutation.isPending || !file}
              className="h-11 px-8 rounded-xl bg-schooltrack-action hover:bg-blue-700 text-white shadow-md shadow-blue-900/10 active:scale-95 transition-all border-0"
            >
              {importMutation.isPending ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Importation...
                </>
              ) : (
                <>
                  <CheckCircle2 className="w-4 h-4 mr-2" />
                  Lancer l'importation
                </>
              )}
            </Button>
          </div>
        </div>

        <div className="space-y-6">
          <Card className="border-slate-200 shadow-sm bg-white">
            <CardHeader className="pb-4 border-b border-slate-50">
              <CardTitle className="text-lg text-schooltrack-primary">Directives</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 pt-4 text-sm text-slate-600">
              <div className="space-y-2">
                <p className="font-semibold text-slate-900 flex items-center gap-2">
                  <div className="w-1.5 h-1.5 bg-schooltrack-action rounded-full" />
                  Colonnes requises
                </p>
                <p className="pl-3.5 border-l border-slate-100">nom, prenom</p>
              </div>
              <div className="space-y-2">
                <p className="font-semibold text-slate-900 flex items-center gap-2">
                  <div className="w-1.5 h-1.5 bg-slate-300 rounded-full" />
                  Colonnes optionnelles
                </p>
                <p className="pl-3.5 border-l border-slate-100">email, classe</p>
              </div>
              <div className="pt-4 border-t border-slate-100">
                <p className="text-xs text-slate-400 leading-relaxed italic">
                  Note : Si un élève avec le même nom et prénom existe déjà dans la même classe, il sera ignoré pour éviter les doublons.
                </p>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
